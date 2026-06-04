# Mundial 2026 · App de Predicciones
## Instrucciones de instalación

---

## Paso 1 — Supabase (base de datos)

1. Ve a [supabase.com](https://supabase.com) → tu proyecto
2. Abre **SQL Editor** → **New query**
3. Pega todo el contenido de `schema.sql` y ejecuta
4. Verifica que diga:
   - `Grupos creados: 12`
   - `Equipos creados: 48`
   - `Partidos creados: 72`

---

## Paso 2 — Configurar la app

Abre `app.html` y busca esta sección al inicio del `<script>`:

```javascript
const SUPABASE_URL = 'https://TU_PROJECT.supabase.co';
const SUPABASE_ANON_KEY = 'TU_ANON_KEY';
const ADMIN_PASSWORD = 'mundial2026admin'; // ← Cambia esto
```

**Dónde encontrar tus credenciales:**
- En Supabase → Settings → API
- Copia `Project URL` y `anon public key`

---

## Paso 3 — Desplegar la app

### Opción A: Vercel (recomendado, gratis)
1. Sube `app.html` a un repositorio de GitHub
2. Ve a [vercel.com](https://vercel.com) → New Project
3. Importa el repo → Deploy
4. Tu URL quedará como: `https://tu-app.vercel.app`

### Opción B: Netlify (gratis)
1. Ve a [netlify.com](https://netlify.com) → Add new site → Deploy manually
2. Arrastra la carpeta con `app.html`
3. Tu URL quedará como: `https://tu-app.netlify.app`

### Opción C: GitHub Pages (gratis)
1. Crea un repo en GitHub, renombra el archivo a `index.html`
2. Settings → Pages → Deploy from main branch

---

## Paso 4 — Como Admin

1. Ve a tu URL desplegada
2. Haz clic en **"Entrar como admin"** (en la parte inferior del formulario)
3. Usa la contraseña que configuraste en `ADMIN_PASSWORD`
4. Desde el Dashboard puedes:
   - **Generar links** → escribe nombre + email → copiar link → enviárselo
   - **Ingresar resultados** → aparecen los partidos que ya empezaron
   - **Confirmar ganadores de grupo** → al terminar la fase de grupos

---

## Paso 5 — Enviar links a participantes

Desde el Dashboard verás la tabla de participantes con el botón **Copiar** junto a cada uno.

El link se ve así:
```
https://tu-app.vercel.app?token=abc123xyz456
```

La persona entra, escribe su nombre y email, y queda registrada automáticamente.

---

## Sistema de puntos

| Acierto | Puntos |
|---------|--------|
| Resultado correcto de un partido | 3 pts |
| Ganador de grupo correcto | 5 pts |

---

## Estructura de archivos

```
mundial2026/
├── app.html      ← La app completa (frontend)
└── schema.sql    ← Base de datos (ejecutar en Supabase)
```

---

## Notas importantes

- **Los partidos cierran automáticamente** al llegar la hora de inicio
- **Los equipos** en el schema son una estimación — los clasificados reales se confirman en marzo 2026
- **Partidos eliminatorios** (ronda de 32, octavos, etc.) se pueden agregar en Supabase cuando se conozcan los clasificados
- **Ranking** se actualiza en tiempo real cada vez que el admin ingresa un resultado

---

## Soporte

Si necesitas ajustar equipos o partidos, ve a Supabase → Table Editor y edita directamente las tablas `teams` y `matches`.
