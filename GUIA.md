# La Perfumisa: cómo poner tu página en línea

Tu página se publica gratis en GitHub y se actualiza sola todos los días a las 6:00 a.m. con los precios y la disponibilidad de Sublime.

## Parte 1. Crear la cuenta y el repositorio (una sola vez)

1. Entra a **github.com** con tu cuenta (`maritzamagana21-del`).
2. Arriba a la derecha, haz clic en **+** y luego en **New repository**.
   - **Repository name:** `catalogo`
   - Marca **Public**. Es obligatorio para publicar gratis.
   - Haz clic en **Create repository**.

## Parte 2. Subir los archivos

3. En el repositorio nuevo, haz clic en **uploading an existing file**.
4. Abre la carpeta `la-perfumisa` en tu computadora y **arrastra todo su contenido** a la página de GitHub:
   - `generar.ps1`
   - `config.json`
   - `incrementos-por-marca.csv`
   - `.gitignore`
   - `GUIA.md`
   - la carpeta `plantillas`
5. Abajo, haz clic en **Commit changes**.
6. Ahora sube el archivo de actualización diaria. Haz clic en **Add file**, luego en **Create new file**.
   - En el nombre escribe exactamente: `.github/workflows/actualizar.yml`
   - Abre el archivo `actualizar.yml` de tu carpeta con el Bloc de notas, copia todo y pégalo.
   - Haz clic en **Commit changes**.

## Parte 3. Activar la página

7. En el repositorio entra a **Settings**, luego a **Pages**.
8. En **Source** elige **GitHub Actions**.
9. Entra a la pestaña **Actions**, elige **Actualizar catálogo** y haz clic en **Run workflow**.
   - La primera vez tarda unos 10 minutos, porque descarga y limpia las 565 fotos. Después tarda 2 o 3 minutos al día.
10. Cuando aparezca la palomita verde, tu página estará en `https://maritzamagana21-del.github.io/catalogo/`.

## Parte 4. Conectar con WhatsApp Business

11. Entra a **business.facebook.com/commerce** (Administrador de ventas de Meta) y crea un catálogo de tipo **Comercio electrónico**.
12. En **Catálogo**, luego **Fuentes de datos**, agrega productos con **Feed de datos**, opción **Programar actualizaciones**, y pega esta dirección:
    `https://maritzamagana21-del.github.io/catalogo/catalogo-meta.csv`
    Elige que se actualice **diariamente** (por ejemplo a las 8:00 a.m.).
13. En la app de WhatsApp Business ve a **Herramientas**, luego **Catálogo**, y conecta el catálogo de Meta que acabas de crear.

## Lo que tendrás que hacer de vez en cuando

- **Cambiar un aumento:** en GitHub abre `incrementos-por-marca.csv`, haz clic en el lápiz ✏️, cambia el número y guarda con **Commit changes**. La página se actualiza en unos minutos.
  También puedes usar porcentaje, por ejemplo `Versace,15%`.
- **Marca nueva:** si Sublime agrega una marca que no está en tu lista, sus perfumes **no se publican** y GitHub te manda un aviso (en **Issues**, y te llega por correo). Agrega la marca con su aumento en `incrementos-por-marca.csv`.
- **Perfumes agotados:** se ocultan solos y vuelven a aparecer cuando Sublime los tenga de nuevo.
- **Actualizar al momento:** entra a **Actions**, luego **Actualizar catálogo**, y haz clic en **Run workflow**.

## Si algo falla

Si una actualización falla (por ejemplo, porque Sublime cambió su página), GitHub te avisa por correo y tu página **se queda con los últimos datos buenos**: no se borra.
