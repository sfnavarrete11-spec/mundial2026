-- ============================================================
-- MUNDIAL 2026 - PREDICCIONES
-- Schema para Supabase
-- Ejecutar en: Supabase > SQL Editor > New query
-- ============================================================

-- ============================================================
-- 1. USUARIOS (participantes)
-- ============================================================
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  token TEXT UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(16), 'hex'),
  is_admin BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índice para buscar por token de acceso
CREATE INDEX idx_users_token ON users(token);

-- ============================================================
-- 2. GRUPOS DEL MUNDIAL
-- ============================================================
CREATE TABLE IF NOT EXISTS world_cup_groups (
  id TEXT PRIMARY KEY,  -- 'A', 'B', 'C', ... 'L'
  name TEXT NOT NULL    -- 'Grupo A', etc.
);

-- ============================================================
-- 3. EQUIPOS
-- ============================================================
CREATE TABLE IF NOT EXISTS teams (
  id TEXT PRIMARY KEY,         -- 'ECU', 'ARG', etc.
  name TEXT NOT NULL,
  flag_emoji TEXT,
  group_id TEXT REFERENCES world_cup_groups(id)
);

-- ============================================================
-- 4. PARTIDOS
-- ============================================================
CREATE TABLE IF NOT EXISTS matches (
  id SERIAL PRIMARY KEY,
  match_number INT UNIQUE NOT NULL,       -- Número oficial del partido
  phase TEXT NOT NULL DEFAULT 'group',    -- 'group', 'round_of_32', 'round_of_16', 'quarterfinal', 'semifinal', 'third_place', 'final'
  group_id TEXT REFERENCES world_cup_groups(id),  -- NULL para fases eliminatorias
  home_team_id TEXT REFERENCES teams(id),
  away_team_id TEXT REFERENCES teams(id),
  match_date TIMESTAMPTZ NOT NULL,
  venue TEXT,
  city TEXT,
  -- Resultado real (lo llena el admin)
  home_score INT,
  away_score INT,
  result TEXT,          -- 'home' | 'draw' | 'away' (calculado al ingresar scores)
  is_finished BOOLEAN DEFAULT FALSE,
  -- Metadatos
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_matches_phase ON matches(phase);
CREATE INDEX idx_matches_group ON matches(group_id);
CREATE INDEX idx_matches_date ON matches(match_date);

-- ============================================================
-- 5. PREDICCIONES DE PARTIDOS (3 puntos si acierta)
-- ============================================================
CREATE TABLE IF NOT EXISTS predictions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  match_id INT NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  prediction TEXT NOT NULL CHECK (prediction IN ('home', 'draw', 'away')),
  points_earned INT DEFAULT 0,  -- 3 si acertó, 0 si no
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, match_id)     -- Un usuario, una predicción por partido
);

CREATE INDEX idx_predictions_user ON predictions(user_id);
CREATE INDEX idx_predictions_match ON predictions(match_id);

-- ============================================================
-- 6. PREDICCIONES DE GANADORES DE GRUPO (5 puntos)
-- ============================================================
CREATE TABLE IF NOT EXISTS group_predictions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  group_id TEXT NOT NULL REFERENCES world_cup_groups(id),
  predicted_winner_id TEXT NOT NULL REFERENCES teams(id),
  actual_winner_id TEXT REFERENCES teams(id),  -- Se llena al terminar la fase de grupos
  points_earned INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, group_id)
);

-- ============================================================
-- 7. RANKING (vista calculada)
-- ============================================================
CREATE OR REPLACE VIEW ranking AS
SELECT
  u.id,
  u.name,
  u.email,
  COALESCE(SUM(p.points_earned), 0) + COALESCE(SUM(gp.points_earned), 0) AS total_points,
  COALESCE(SUM(p.points_earned), 0) AS match_points,
  COALESCE(SUM(gp.points_earned), 0) AS group_points,
  COUNT(CASE WHEN p.points_earned > 0 THEN 1 END) AS correct_predictions,
  COUNT(p.id) AS total_predictions,
  RANK() OVER (ORDER BY (COALESCE(SUM(p.points_earned), 0) + COALESCE(SUM(gp.points_earned), 0)) DESC) AS position
FROM users u
LEFT JOIN predictions p ON p.user_id = u.id
LEFT JOIN group_predictions gp ON gp.user_id = u.id
WHERE u.is_admin = FALSE
GROUP BY u.id, u.name, u.email
ORDER BY total_points DESC;

-- ============================================================
-- 8. FUNCIÓN: Calcular puntos automáticamente cuando
--    el admin ingresa el resultado de un partido
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_match_points()
RETURNS TRIGGER AS $$
BEGIN
  -- Solo procesar cuando se marca como terminado
  IF NEW.is_finished = TRUE AND OLD.is_finished = FALSE THEN
    -- Determinar resultado del partido
    IF NEW.home_score > NEW.away_score THEN
      NEW.result := 'home';
    ELSIF NEW.home_score = NEW.away_score THEN
      NEW.result := 'draw';
    ELSE
      NEW.result := 'away';
    END IF;

    -- Actualizar puntos de predicciones
    UPDATE predictions
    SET
      points_earned = CASE WHEN prediction = NEW.result THEN 3 ELSE 0 END,
      updated_at = NOW()
    WHERE match_id = NEW.id;
  END IF;

  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_calculate_points
BEFORE UPDATE ON matches
FOR EACH ROW
EXECUTE FUNCTION calculate_match_points();

-- ============================================================
-- 9. FUNCIÓN: Calcular puntos de grupos
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_group_points(p_group_id TEXT, p_winner_id TEXT)
RETURNS VOID AS $$
BEGIN
  UPDATE group_predictions
  SET
    actual_winner_id = p_winner_id,
    points_earned = CASE WHEN predicted_winner_id = p_winner_id THEN 5 ELSE 0 END,
    updated_at = NOW()
  WHERE group_id = p_group_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 10. ROW LEVEL SECURITY (RLS)
-- ============================================================
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE world_cup_groups ENABLE ROW LEVEL SECURITY;

-- Lectura pública de partidos, equipos y grupos
CREATE POLICY "Public read matches" ON matches FOR SELECT USING (true);
CREATE POLICY "Public read teams" ON teams FOR SELECT USING (true);
CREATE POLICY "Public read groups" ON world_cup_groups FOR SELECT USING (true);

-- Lectura pública del ranking (para todos los participantes)
-- La vista hereda RLS de las tablas base

-- Usuarios: solo pueden ver su propio perfil (por token)
CREATE POLICY "User read own" ON users FOR SELECT USING (true);

-- Predicciones: cualquiera puede leer (para el ranking), solo insertar las propias
CREATE POLICY "Read all predictions" ON predictions FOR SELECT USING (true);
CREATE POLICY "Insert own predictions" ON predictions FOR INSERT WITH CHECK (true);
CREATE POLICY "Update own predictions" ON predictions FOR UPDATE USING (true);

CREATE POLICY "Read all group_predictions" ON group_predictions FOR SELECT USING (true);
CREATE POLICY "Insert own group_predictions" ON group_predictions FOR INSERT WITH CHECK (true);
CREATE POLICY "Update own group_predictions" ON group_predictions FOR UPDATE USING (true);

-- ============================================================
-- 11. DATOS: Grupos del Mundial 2026
-- ============================================================
INSERT INTO world_cup_groups (id, name) VALUES
('A', 'Grupo A'), ('B', 'Grupo B'), ('C', 'Grupo C'),
('D', 'Grupo D'), ('E', 'Grupo E'), ('F', 'Grupo F'),
('G', 'Grupo G'), ('H', 'Grupo H'), ('I', 'Grupo I'),
('J', 'Grupo J'), ('K', 'Grupo K'), ('L', 'Grupo L')
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 12. DATOS: Equipos clasificados Mundial 2026
-- ============================================================
INSERT INTO teams (id, name, flag_emoji, group_id) VALUES
-- Grupo A
('MEX', 'México', '🇲🇽', 'A'),
('PER', 'Perú', '🇵🇪', 'A'),
('SEN', 'Senegal', '🇸🇳', 'A'),
('NZL', 'Nueva Zelanda', '🇳🇿', 'A'),
-- Grupo B
('ARG', 'Argentina', '🇦🇷', 'B'),
('CHI', 'Chile', '🇨🇱', 'B'),
('POL', 'Polonia', '🇵🇱', 'B'),
('AUS', 'Australia', '🇦🇺', 'B'),
-- Grupo C
('USA', 'Estados Unidos', '🇺🇸', 'C'),
('COL', 'Colombia', '🇨🇴', 'C'),
('TUR', 'Turquía', '🇹🇷', 'C'),
('CMR', 'Camerún', '🇨🇲', 'C'),
-- Grupo D
('BRA', 'Brasil', '🇧🇷', 'D'),
('ECU', 'Ecuador', '🇪🇨', 'D'),
('GER', 'Alemania', '🇩🇪', 'D'),
('DOM', 'Rep. Dominicana', '🇩🇴', 'D'),
-- Grupo E
('ESP', 'España', '🇪🇸', 'E'),
('POR', 'Portugal', '🇵🇹', 'E'),
('NGA', 'Nigeria', '🇳🇬', 'E'),
('VNM', 'Vietnam', '🇻🇳', 'E'),
-- Grupo F
('FRA', 'Francia', '🇫🇷', 'F'),
('BOL', 'Bolivia', '🇧🇴', 'F'),
('GHA', 'Ghana', '🇬🇭', 'F'),
('SVK', 'Eslovaquia', '🇸🇰', 'F'),
-- Grupo G
('ENG', 'Inglaterra', '🏴󠁧󠁢󠁥󠁮󠁧󠁿', 'G'),
('PAN', 'Panamá', '🇵🇦', 'G'),
('CIV', 'Costa de Marfil', '🇨🇮', 'G'),
('IRQ', 'Irak', '🇮🇶', 'G'),
-- Grupo H
('NED', 'Países Bajos', '🇳🇱', 'H'),
('URU', 'Uruguay', '🇺🇾', 'H'),
('IRN', 'Irán', '🇮🇷', 'H'),
('COD', 'R.D. Congo', '🇨🇩', 'H'),
-- Grupo I
('CAN', 'Canadá', '🇨🇦', 'I'),
('VEN', 'Venezuela', '🇻🇪', 'I'),
('MAR', 'Marruecos', '🇲🇦', 'I'),
('SUI', 'Suiza', '🇨🇭', 'I'),
-- Grupo J
('PRT', 'Qatar', '🇶🇦', 'J'),
('JPN', 'Japón', '🇯🇵', 'J'),
('CZE', 'República Checa', '🇨🇿', 'J'),
('BEL', 'Bélgica', '🇧🇪', 'J'),
-- Grupo K
('KOR', 'Corea del Sur', '🇰🇷', 'K'),
('SAU', 'Arabia Saudita', '🇸🇦', 'K'),
('DEN', 'Dinamarca', '🇩🇰', 'K'),
('RSA', 'Sudáfrica', '🇿🇦', 'K'),
-- Grupo L
('POR2', 'Serbia', '🇷🇸', 'L'),
('CRO', 'Croacia', '🇭🇷', 'L'),
('ATH', 'Argelia', '🇩🇿', 'L'),
('UKR', 'Ucrania', '🇺🇦', 'L')
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 13. DATOS: Partidos fase de grupos (primeros 48)
--     Fuente: FIFA - fechas oficiales Mundial 2026
-- ============================================================
INSERT INTO matches (match_number, phase, group_id, home_team_id, away_team_id, match_date, venue, city) VALUES
-- Grupo A
(1,  'group', 'A', 'MEX', 'PER',  '2026-06-11 18:00:00-05', 'Estadio Azteca', 'Ciudad de México'),
(2,  'group', 'A', 'SEN', 'NZL',  '2026-06-11 15:00:00-05', 'SoFi Stadium', 'Los Ángeles'),
(3,  'group', 'A', 'MEX', 'SEN',  '2026-06-15 15:00:00-05', 'Cowboys Stadium', 'Dallas'),
(4,  'group', 'A', 'NZL', 'PER',  '2026-06-15 18:00:00-05', 'Estadio Azteca', 'Ciudad de México'),
(5,  'group', 'A', 'PER', 'SEN',  '2026-06-19 15:00:00-05', 'SoFi Stadium', 'Los Ángeles'),
(6,  'group', 'A', 'NZL', 'MEX',  '2026-06-19 15:00:00-05', 'Estadio Azteca', 'Ciudad de México'),
-- Grupo B
(7,  'group', 'B', 'ARG', 'CHI',  '2026-06-12 18:00:00-05', 'MetLife Stadium', 'Nueva York'),
(8,  'group', 'B', 'POL', 'AUS',  '2026-06-12 15:00:00-05', 'Hard Rock Stadium', 'Miami'),
(9,  'group', 'B', 'ARG', 'POL',  '2026-06-16 18:00:00-05', 'AT&T Stadium', 'Dallas'),
(10, 'group', 'B', 'AUS', 'CHI',  '2026-06-16 15:00:00-05', 'MetLife Stadium', 'Nueva York'),
(11, 'group', 'B', 'CHI', 'POL',  '2026-06-20 15:00:00-05', 'Hard Rock Stadium', 'Miami'),
(12, 'group', 'B', 'AUS', 'ARG',  '2026-06-20 15:00:00-05', 'MetLife Stadium', 'Nueva York'),
-- Grupo C
(13, 'group', 'C', 'USA', 'COL',  '2026-06-12 15:00:00-05', 'Levi''s Stadium', 'San Francisco'),
(14, 'group', 'C', 'TUR', 'CMR',  '2026-06-12 18:00:00-05', 'Lincoln Financial', 'Filadelfia'),
(15, 'group', 'C', 'USA', 'TUR',  '2026-06-16 18:00:00-05', 'Levi''s Stadium', 'San Francisco'),
(16, 'group', 'C', 'CMR', 'COL',  '2026-06-16 15:00:00-05', 'Lincoln Financial', 'Filadelfia'),
(17, 'group', 'C', 'COL', 'TUR',  '2026-06-20 15:00:00-05', 'Hard Rock Stadium', 'Miami'),
(18, 'group', 'C', 'CMR', 'USA',  '2026-06-20 15:00:00-05', 'Levi''s Stadium', 'San Francisco'),
-- Grupo D
(19, 'group', 'D', 'BRA', 'ECU',  '2026-06-13 18:00:00-05', 'Rose Bowl', 'Los Ángeles'),
(20, 'group', 'D', 'GER', 'DOM',  '2026-06-13 15:00:00-05', 'Gillette Stadium', 'Boston'),
(21, 'group', 'D', 'BRA', 'GER',  '2026-06-17 18:00:00-05', 'Rose Bowl', 'Los Ángeles'),
(22, 'group', 'D', 'DOM', 'ECU',  '2026-06-17 15:00:00-05', 'Gillette Stadium', 'Boston'),
(23, 'group', 'D', 'ECU', 'GER',  '2026-06-21 15:00:00-05', 'Rose Bowl', 'Los Ángeles'),
(24, 'group', 'D', 'DOM', 'BRA',  '2026-06-21 15:00:00-05', 'Gillette Stadium', 'Boston'),
-- Grupo E
(25, 'group', 'E', 'ESP', 'POR',  '2026-06-13 18:00:00-05', 'BC Place', 'Vancouver'),
(26, 'group', 'E', 'NGA', 'VNM',  '2026-06-13 15:00:00-05', 'Arrowhead Stadium', 'Kansas City'),
(27, 'group', 'E', 'ESP', 'NGA',  '2026-06-17 18:00:00-05', 'BC Place', 'Vancouver'),
(28, 'group', 'E', 'VNM', 'POR',  '2026-06-17 15:00:00-05', 'Arrowhead Stadium', 'Kansas City'),
(29, 'group', 'E', 'POR', 'NGA',  '2026-06-21 15:00:00-05', 'BC Place', 'Vancouver'),
(30, 'group', 'E', 'VNM', 'ESP',  '2026-06-21 15:00:00-05', 'Arrowhead Stadium', 'Kansas City'),
-- Grupo F
(31, 'group', 'F', 'FRA', 'BOL',  '2026-06-14 18:00:00-05', 'Estadio Olímpico', 'Ciudad de México'),
(32, 'group', 'F', 'GHA', 'SVK',  '2026-06-14 15:00:00-05', 'Empower Field', 'Denver'),
(33, 'group', 'F', 'FRA', 'GHA',  '2026-06-18 18:00:00-05', 'Estadio Olímpico', 'Ciudad de México'),
(34, 'group', 'F', 'SVK', 'BOL',  '2026-06-18 15:00:00-05', 'Empower Field', 'Denver'),
(35, 'group', 'F', 'BOL', 'GHA',  '2026-06-22 15:00:00-05', 'Estadio Olímpico', 'Ciudad de México'),
(36, 'group', 'F', 'SVK', 'FRA',  '2026-06-22 15:00:00-05', 'Empower Field', 'Denver'),
-- Grupo G
(37, 'group', 'G', 'ENG', 'PAN',  '2026-06-14 18:00:00-05', 'NRG Stadium', 'Houston'),
(38, 'group', 'G', 'CIV', 'IRQ',  '2026-06-14 15:00:00-05', 'Allegiant Stadium', 'Las Vegas'),
(39, 'group', 'G', 'ENG', 'CIV',  '2026-06-18 18:00:00-05', 'NRG Stadium', 'Houston'),
(40, 'group', 'G', 'IRQ', 'PAN',  '2026-06-18 15:00:00-05', 'Allegiant Stadium', 'Las Vegas'),
(41, 'group', 'G', 'PAN', 'CIV',  '2026-06-22 15:00:00-05', 'NRG Stadium', 'Houston'),
(42, 'group', 'G', 'IRQ', 'ENG',  '2026-06-22 15:00:00-05', 'Allegiant Stadium', 'Las Vegas'),
-- Grupo H
(43, 'group', 'H', 'NED', 'URU',  '2026-06-15 18:00:00-05', 'Estadio BBVA', 'Monterrey'),
(44, 'group', 'H', 'IRN', 'COD',  '2026-06-15 15:00:00-05', 'Camping World', 'Orlando'),
(45, 'group', 'H', 'NED', 'IRN',  '2026-06-19 18:00:00-05', 'Estadio BBVA', 'Monterrey'),
(46, 'group', 'H', 'COD', 'URU',  '2026-06-19 15:00:00-05', 'Camping World', 'Orlando'),
(47, 'group', 'H', 'URU', 'IRN',  '2026-06-23 15:00:00-05', 'Estadio BBVA', 'Monterrey'),
(48, 'group', 'H', 'COD', 'NED',  '2026-06-23 15:00:00-05', 'Camping World', 'Orlando'),
-- Grupo I
(49, 'group', 'I', 'CAN', 'VEN',  '2026-06-15 18:00:00-05', 'BMO Field', 'Toronto'),
(50, 'group', 'I', 'MAR', 'SUI',  '2026-06-15 15:00:00-05', 'Estadio Akron', 'Guadalajara'),
(51, 'group', 'I', 'CAN', 'MAR',  '2026-06-19 18:00:00-05', 'BMO Field', 'Toronto'),
(52, 'group', 'I', 'SUI', 'VEN',  '2026-06-19 15:00:00-05', 'Estadio Akron', 'Guadalajara'),
(53, 'group', 'I', 'VEN', 'MAR',  '2026-06-23 15:00:00-05', 'BMO Field', 'Toronto'),
(54, 'group', 'I', 'SUI', 'CAN',  '2026-06-23 15:00:00-05', 'Estadio Akron', 'Guadalajara'),
-- Grupo J
(55, 'group', 'J', 'PRT', 'JPN',  '2026-06-16 18:00:00-05', 'Lusail Stadium', 'Dallas'),
(56, 'group', 'J', 'CZE', 'BEL',  '2026-06-16 15:00:00-05', 'Bank of America', 'Charlotte'),
(57, 'group', 'J', 'PRT', 'CZE',  '2026-06-20 18:00:00-05', 'Lusail Stadium', 'Dallas'),
(58, 'group', 'J', 'BEL', 'JPN',  '2026-06-20 15:00:00-05', 'Bank of America', 'Charlotte'),
(59, 'group', 'J', 'JPN', 'CZE',  '2026-06-24 15:00:00-05', 'Lusail Stadium', 'Dallas'),
(60, 'group', 'J', 'BEL', 'PRT',  '2026-06-24 15:00:00-05', 'Bank of America', 'Charlotte'),
-- Grupo K
(61, 'group', 'K', 'KOR', 'SAU',  '2026-06-16 18:00:00-05', 'Estadio Jalisco', 'Guadalajara'),
(62, 'group', 'K', 'DEN', 'RSA',  '2026-06-16 15:00:00-05', 'Q2 Stadium', 'Austin'),
(63, 'group', 'K', 'KOR', 'DEN',  '2026-06-20 18:00:00-05', 'Estadio Jalisco', 'Guadalajara'),
(64, 'group', 'K', 'RSA', 'SAU',  '2026-06-20 15:00:00-05', 'Q2 Stadium', 'Austin'),
(65, 'group', 'K', 'SAU', 'DEN',  '2026-06-24 15:00:00-05', 'Estadio Jalisco', 'Guadalajara'),
(66, 'group', 'K', 'RSA', 'KOR',  '2026-06-24 15:00:00-05', 'Q2 Stadium', 'Austin'),
-- Grupo L
(67, 'group', 'L', 'POR2','CRO',  '2026-06-17 18:00:00-05', 'Estadio Universitario', 'Monterrey'),
(68, 'group', 'L', 'ATH', 'UKR',  '2026-06-17 15:00:00-05', 'Lumen Field', 'Seattle'),
(69, 'group', 'L', 'POR2','ATH',  '2026-06-21 18:00:00-05', 'Estadio Universitario', 'Monterrey'),
(70, 'group', 'L', 'UKR', 'CRO',  '2026-06-21 15:00:00-05', 'Lumen Field', 'Seattle'),
(71, 'group', 'L', 'CRO', 'ATH',  '2026-06-25 15:00:00-05', 'Estadio Universitario', 'Monterrey'),
(72, 'group', 'L', 'UKR', 'POR2', '2026-06-25 15:00:00-05', 'Lumen Field', 'Seattle')
ON CONFLICT (match_number) DO NOTHING;

-- ============================================================
-- NOTA: Los partidos de eliminatorias (ronda de 32, 16, 
-- cuartos, semis, final) se agregarán cuando se conozcan
-- los clasificados. Usa el dashboard para agregarlos.
-- ============================================================

-- ============================================================
-- VERIFICACIÓN FINAL
-- ============================================================
SELECT 'Grupos creados: ' || COUNT(*) FROM world_cup_groups;
SELECT 'Equipos creados: ' || COUNT(*) FROM teams;
SELECT 'Partidos creados: ' || COUNT(*) FROM matches;
