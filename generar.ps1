# Genera el sitio de La Perfumisa a partir de la tienda de origen.
# Uso: powershell -ExecutionPolicy Bypass -File generar.ps1 -Salida _sitio -BaseUrl https://usuario.github.io/repo/
param(
  [string]$Salida = "_sitio",
  [string]$BaseUrl = "http://localhost:8765/",
  [string]$DatosLocales = ""   # solo para pruebas: carpeta con <coleccion>-<pagina>.json ya descargados
)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$raiz = $PSScriptRoot
if (-not $BaseUrl.EndsWith("/")) { $BaseUrl += "/" }
$utf8 = New-Object Text.UTF8Encoding($false)

# ---------- Procesamiento de imagenes (deteccion y borrado de la leyenda "Nueva imagen") ----------
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
public static class ImgTool {
  static bool Near(int v, int t, int tol) { return Math.Abs(v - t) < tol; }
  // Devuelve 1 si encontro y borro la leyenda, 0 si no. Guarda JPEG redimensionado en outPath.
  public static string Limpiar(byte[] data, string outPath, int outW, int quality) {
    using (var ms = new MemoryStream(data))
    using (var src = new Bitmap(ms)) {
      int W = src.Width, H = src.Height;
      var bmp = new Bitmap(W, H, PixelFormat.Format24bppRgb);
      using (var g = Graphics.FromImage(bmp)) { g.Clear(Color.White); g.DrawImage(src, 0, 0, W, H); }
      var bd = bmp.LockBits(new Rectangle(0, 0, W, H), ImageLockMode.ReadWrite, PixelFormat.Format24bppRgb);
      int st = bd.Stride; byte[] px = new byte[st * H];
      Marshal.Copy(bd.Scan0, px, 0, px.Length);
      int found = 0;
      if (Math.Abs(W - H) <= W / 50) {
        int rx0 = (int)(W * 0.68), rx1 = (int)(W * 0.95), ry0 = (int)(H * 0.87), ry1 = (int)(H * 0.93);
        int n = 0, tot = 0;
        for (int y = ry0; y < ry1; y++) for (int x = rx0; x < rx1; x++) {
          int p = y * st + x * 3; tot++;
          if (Near(px[p + 2], 78, 24) && Near(px[p + 1], 127, 24) && Near(px[p], 196, 24)) n++;
        }
        if (tot > 0 && n > tot * 0.35) {
          found = 1;
          int x0 = (int)(W * 0.506), x1 = Math.Min(W - 1, (int)(W * 0.978));
          int y0 = (int)(H * 0.838), y1 = Math.Min(H - 2, (int)(H * 0.985));
          int h = y1 - y0 + 1, fs = (int)(h * 0.55);
          for (int x = x0; x <= x1; x++) {
            int a = (y0 - 1) * st + x * 3, b = (y1 + 1) * st + x * 3;
            for (int i = 0; i < h; i++) {
              double t = i < fs ? 0 : (double)(i - fs + 1) / (h - fs + 1);
              int p = (y0 + i) * st + x * 3;
              for (int c = 0; c < 3; c++) px[p + c] = (byte)(px[a + c] * (1 - t) + px[b + c] * t);
            }
          }
          Marshal.Copy(px, 0, bd.Scan0, px.Length);
        }
      }
      bmp.UnlockBits(bd);
      int ow = Math.Min(outW, W), oh = (int)Math.Round((double)H * ow / W);
      using (var outBmp = new Bitmap(ow, oh, PixelFormat.Format24bppRgb)) {
        using (var g = Graphics.FromImage(outBmp)) {
          g.InterpolationMode = InterpolationMode.HighQualityBicubic;
          g.DrawImage(bmp, 0, 0, ow, oh);
        }
        var enc = Array.Find(ImageCodecInfo.GetImageEncoders(), e => e.MimeType == "image/jpeg");
        var ps = new EncoderParameters(1); ps.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, (long)quality);
        outBmp.Save(outPath, enc, ps);
      }
      bmp.Dispose();
      return found == 1 ? "limpia" : "normal";
    }
  }
}
"@

function Con-Reintentos([scriptblock]$accion) {
  $espera = 5
  for ($i = 1; $i -le 6; $i++) {
    try { return & $accion } catch {
      if ($i -eq 6) { throw }
      Write-Warning "Intento $i fallido ($($_.Exception.Message)); reintentando en $espera s"
      Start-Sleep -Seconds $espera; $espera *= 2
    }
  }
}
function Leer-Texto($ruta) { [IO.File]::ReadAllText($ruta, [Text.Encoding]::UTF8) }
function Html($s) { [Net.WebUtility]::HtmlEncode([string]$s) }
function Csv($s) { '"' + ([string]$s).Replace('"', '""') + '"' }
function Precio($n) { '$' + $n.ToString("N2", [Globalization.CultureInfo]"es-MX") }

$cfg = Leer-Texto "$raiz\config.json" | ConvertFrom-Json

# ---------- Incrementos por marca ----------
$inc = @{}
Import-Csv "$raiz\incrementos-por-marca.csv" -Encoding UTF8 | ForEach-Object {
  $m = ([string]$_.Marca).Trim(); $v = ([string]$_.Incremento).Trim()
  if ($m -and $v) { $inc[$m] = $v }
}
function Aplicar($precio, $regla) {
  if ($regla.EndsWith("%")) { return [math]::Round($precio * (1 + [double]$regla.TrimEnd("%") / 100), 0) }
  return $precio + [double]$regla
}

# ---------- Descargar productos ----------
$productos = @(); $vistos = @{}
foreach ($col in $cfg.colecciones) {
  $pag = 1
  do {
    $url = "$($cfg.tienda_origen)/collections/$($col.handle)/products.json?limit=250&page=$pag"
    if ($DatosLocales) {
      $json = Leer-Texto (Join-Path $DatosLocales "$($col.handle)-$pag.json") | ConvertFrom-Json
    } else {
      $json = (Con-Reintentos { Invoke-WebRequest -UseBasicParsing $url }).Content | ConvertFrom-Json
      Start-Sleep -Milliseconds 500
    }
    foreach ($p in $json.products) {
      if ($vistos.ContainsKey($p.handle)) { continue }
      $vistos[$p.handle] = 1
      $v = $p.variants | Sort-Object { [double]$_.price } | Select-Object -First 1
      $productos += [pscustomobject]@{
        h = ($p.handle -replace '[^a-zA-Z0-9_-]', '-')
        t = ($p.title.Trim() -replace '\s+', ' ')
        b = ([string]$p.vendor).Trim()
        base = [double]$v.price
        disponible = (@($p.variants.available) -contains $true)
        src = $(if ($p.images.Count) { ($p.images[0].src -replace '[?&]width=\d+', '') } else { "" })
        g = $col.clave
      }
    }
    $pag++
  } while ($json.products.Count -eq 250)
}
if ($productos.Count -lt 50) { throw "Se descargaron muy pocos productos ($($productos.Count)); se cancela para no publicar un catalogo incompleto." }

$agotados = @($productos | Where-Object { -not $_.disponible })
$disponibles = @($productos | Where-Object { $_.disponible })
$pendientes = @($disponibles | Where-Object { -not $inc.ContainsKey($_.b) })
$publicar = @($disponibles | Where-Object { $inc.ContainsKey($_.b) })
foreach ($p in $publicar) { $p | Add-Member -NotePropertyName p -NotePropertyValue (Aplicar $p.base $inc[$p.b]) }

# ---------- Imagenes ----------
$dirImg = Join-Path $raiz "img"
New-Item -ItemType Directory -Force $dirImg | Out-Null
$manifiesto = @{}
if (Test-Path "$raiz\imagenes.json") {
  (Leer-Texto "$raiz\imagenes.json" | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $manifiesto[$_.Name] = $_.Value }
}
$wc = New-Object Net.WebClient
$nuevas = 0; $limpias = @(); $fallidas = 0
foreach ($p in $publicar) {
  $archivo = Join-Path $dirImg "$($p.h).jpg"
  if (-not $p.src) { continue }
  if ((Test-Path $archivo) -and $manifiesto[$p.h] -eq $p.src) { continue }
  try {
    $sep = $(if ($p.src.Contains("?")) { "&" } else { "?" })
    $u = $p.src + $sep + "width=1000"
    $bytes = Con-Reintentos { $wc.DownloadData($u) }
    if ([ImgTool]::Limpiar($bytes, $archivo, 800, 85) -eq "limpia") { $limpias += $p.t }
    $manifiesto[$p.h] = $p.src; $nuevas++
  } catch { $fallidas++; Write-Warning "No se pudo descargar la imagen de $($p.t): $_" }
}
$orden = [ordered]@{}; $manifiesto.Keys | Sort-Object | ForEach-Object { $orden[$_] = $manifiesto[$_] }
[IO.File]::WriteAllText("$raiz\imagenes.json", ($orden | ConvertTo-Json), $utf8)

# ---------- Sitio ----------
if (Test-Path $Salida) { Remove-Item -Recurse -Force $Salida }
New-Item -ItemType Directory -Force "$Salida\producto", "$Salida\img" | Out-Null
$mx = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, "Central Standard Time (Mexico)")
$fecha = $mx.ToString("d 'de' MMMM 'de' yyyy", [Globalization.CultureInfo]"es-MX")
$etiquetas = @{}; foreach ($c in $cfg.colecciones) { $etiquetas[$c.clave] = $c.etiqueta }
$wa = "https://wa.me/$($cfg.whatsapp)"

$conImagen = @{}
foreach ($p in $publicar) {
  $f = Join-Path $dirImg "$($p.h).jpg"
  if (Test-Path $f) { Copy-Item $f "$Salida\img\"; $conImagen[$p.h] = 1 }
}

$datos = @($publicar | Sort-Object t | ForEach-Object {
  [ordered]@{ t = $_.t; b = $_.b; p = $_.p; g = $_.g; h = $_.h; i = [bool]$conImagen[$_.h] }
})
$jsonDatos = ConvertTo-Json -InputObject $datos -Compress -Depth 3
$jsonEtiq = ConvertTo-Json -InputObject $etiquetas -Compress

$inicio = (Leer-Texto "$raiz\plantillas\inicio.html").
  Replace("{{NOMBRE}}", (Html $cfg.nombre)).
  Replace("{{WHATSAPP}}", $wa).
  Replace("{{FECHA}}", $fecha).
  Replace("{{BASE_URL}}", $BaseUrl).
  Replace("{{ETIQUETAS}}", $jsonEtiq).
  Replace("{{DATOS}}", $jsonDatos)
[IO.File]::WriteAllText("$Salida\index.html", $inicio, $utf8)

$plantillaProd = Leer-Texto "$raiz\plantillas\producto.html"
$filasMeta = @("id,title,description,availability,condition,price,link,image_link,brand")
foreach ($p in $publicar) {
  $etq = $etiquetas[$p.g]
  $mensaje = "Hola, me interesa el perfume $($p.t) de $($p.b) ($(Precio $p.p)). " + [char]0x00BF + "Est" + [char]0x00E1 + " disponible?"
  $link = "$($BaseUrl)producto/$($p.h).html"
  $imgUrl = $(if ($conImagen[$p.h]) { "$($BaseUrl)img/$($p.h).jpg" } else { "" })
  $desc = "Perfume para $($etq.ToLower()) de la marca $($p.b): $($p.t)."
  $html = $plantillaProd.
    Replace("{{NOMBRE}}", (Html $cfg.nombre)).
    Replace("{{TITULO}}", (Html $p.t)).
    Replace("{{MARCA}}", (Html $p.b)).
    Replace("{{SECCION}}", (Html $etq)).
    Replace("{{PRECIO}}", (Precio $p.p)).
    Replace("{{PRECIO_NUM}}", $p.p.ToString("0.00", [Globalization.CultureInfo]::InvariantCulture)).
    Replace("{{DESCRIPCION}}", (Html $desc)).
    Replace("{{IMAGEN}}", $(if ($conImagen[$p.h]) { "../img/$($p.h).jpg" } else { "" })).
    Replace("{{IMAGEN_URL}}", $imgUrl).
    Replace("{{URL}}", $link).
    Replace("{{WHATSAPP_PEDIDO}}", "$($wa)?text=$([Uri]::EscapeDataString($mensaje))").
    Replace("{{WHATSAPP}}", $wa).
    Replace("{{FECHA}}", $fecha)
  [IO.File]::WriteAllText("$Salida\producto\$($p.h).html", $html, $utf8)
  if ($imgUrl) {
    $filasMeta += (@($p.h, $p.t, $desc, "in stock", "new", ($p.p.ToString("0.00", [Globalization.CultureInfo]::InvariantCulture) + " MXN"), $link, $imgUrl, $p.b) | ForEach-Object { Csv $_ }) -join ","
  }
}
[IO.File]::WriteAllText("$Salida\catalogo-meta.csv", ($filasMeta -join "`n") + "`n", $utf8)
[IO.File]::WriteAllText("$Salida\.nojekyll", "", $utf8)

# ---------- Marcas sin aumento ----------
$aviso = "$raiz\marcas-nuevas.txt"
if ($pendientes.Count) {
  $lineas = $pendientes | Group-Object b | Sort-Object Name | ForEach-Object {
    "- **$($_.Name)** ($($_.Count) perfume(s)): " + (($_.Group | Select-Object -First 5 | ForEach-Object { $_.t }) -join "; ")
  }
  [IO.File]::WriteAllText($aviso, ($lineas -join "`n") + "`n", $utf8)
} elseif (Test-Path $aviso) { Remove-Item $aviso }

"Productos en la tienda: $($productos.Count)"
"Agotados (ocultos): $($agotados.Count)"
"Sin aumento (ocultos hasta asignar marca): $($pendientes.Count)"
"Publicados: $($publicar.Count)"
"Imagenes nuevas o cambiadas: $nuevas (fallidas: $fallidas)"
"Leyenda 'Nueva imagen' borrada en: $($limpias.Count)"
$limpias | ForEach-Object { "  - $_" }
