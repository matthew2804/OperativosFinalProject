# =============================================================================
# Herramienta de Administracion de Data Center - Integrante 1
# Opciones: 1) Usuarios y ultimo login  2) Filesystems / Discos
# Compatible: Windows PowerShell 5.1+
# Ejecutar: powershell -ExecutionPolicy Bypass -File ".\gestion_usuarios_almacenamiento.ps1"
# =============================================================================

function Write-Separator {
    Write-Host ("-" * 85) -ForegroundColor Cyan
}

function Write-Header {
    param([string]$Titulo)
    Write-Host ""
    Write-Host ("=" * 72) -ForegroundColor Green
    Write-Host "  $Titulo" -ForegroundColor Green
    Write-Host ("=" * 72) -ForegroundColor Green
    Write-Host ""
}

# =============================================================================
# OPCION 1 - Usuarios del sistema y ultimo inicio de sesion
# =============================================================================
function Show-Usuarios {
    Write-Header "USUARIOS DEL SISTEMA Y ULTIMO INICIO DE SESION"

    $usuarios = Get-LocalUser -ErrorAction SilentlyContinue

    if (-not $usuarios) {
        Write-Host "  No se pudieron obtener usuarios locales." -ForegroundColor Yellow
        return
    }

    Write-Host ("{0,-28} {1,-14} {2,-26} {3}" -f "USUARIO", "ESTADO", "ULTIMO LOGIN", "DESCRIPCION") -ForegroundColor White
    Write-Separator

    foreach ($u in $usuarios) {
        $ultimoLogin = if ($u.LastLogon) {
            $u.LastLogon.ToString("yyyy-MM-dd HH:mm:ss")
        } else {
            "Nunca / Sin registro"
        }

        $estado      = if ($u.Enabled) { "Habilitado" } else { "Deshabilitado" }
        $colorEstado = if ($u.Enabled) { "Green" } else { "Red" }
        $desc        = if ($u.Description) { $u.Description } else { "-" }
        if ($desc.Length -gt 20) { $desc = $desc.Substring(0, 19) + "..." }

        Write-Host ("{0,-28} " -f $u.Name)      -NoNewline -ForegroundColor White
        Write-Host ("{0,-14} " -f $estado)       -NoNewline -ForegroundColor $colorEstado
        Write-Host ("{0,-26} " -f $ultimoLogin)  -NoNewline -ForegroundColor Cyan
        Write-Host ("{0}"      -f $desc)                    -ForegroundColor Gray
    }

    Write-Separator
    Write-Host ""
    Write-Host ("  Total de usuarios locales: {0}" -f $usuarios.Count) -ForegroundColor Green

    Write-Host ""
    Write-Host "  Ultimos inicios de sesion (Event Log - ultimos 10 dias):" -ForegroundColor White
    Write-Host ""

    try {
        $eventos = Get-WinEvent -FilterHashtable @{
            LogName   = "Security"
            Id        = 4624
            StartTime = (Get-Date).AddDays(-10)
        } -MaxEvents 30 -ErrorAction Stop |
        Where-Object {
            ($_.Properties[8].Value -eq 2 -or $_.Properties[8].Value -eq 10) -and
            ($_.Properties[5].Value -notmatch "SISTEMA|SYSTEM|\$")
        } | Select-Object -First 10

        if ($eventos) {
            Write-Host ("  {0,-28} {1,-26} {2}" -f "USUARIO", "FECHA Y HORA", "TIPO") -ForegroundColor White
            foreach ($ev in $eventos) {
                $tipo = if ($ev.Properties[8].Value -eq 2) { "Interactivo" } else { "RDP/Remoto" }
                Write-Host ("  {0,-28} {1,-26} {2}" -f `
                    $ev.Properties[5].Value,
                    $ev.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss"),
                    $tipo) -ForegroundColor Cyan
            }
        } else {
            Write-Host "  Sin eventos de login en los ultimos 10 dias." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  No se pudo leer el Event Log de Seguridad." -ForegroundColor Yellow
        Write-Host "  Ejecute PowerShell como Administrador para ver el historial completo." -ForegroundColor DarkGray
    }

    Write-Host ""
}

# =============================================================================
# OPCION 2 - Filesystems / Discos conectados (tamano y espacio libre en bytes)
# =============================================================================
function Show-Filesystems {
    Write-Header "FILESYSTEMS Y DISCOS CONECTADOS AL SISTEMA"

    Write-Host "  Volumenes logicos (unidades de disco):" -ForegroundColor White
    Write-Host ""
    Write-Host ("{0,-7} {1,-22} {2,-22} {3,-22} {4,-22} {5}" -f `
        "UNIDAD", "ETIQUETA", "TAMANO TOTAL (bytes)", "ESPACIO LIBRE (bytes)", "ESPACIO USADO (bytes)", "USO %") `
        -ForegroundColor White
    Write-Separator

    $drives    = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
                 Where-Object { $_.Root -match "^[A-Z]:\\$" }
    $totalAcum = [long]0
    $libreAcum = [long]0

    foreach ($drive in $drives) {
        $totalBytes = [long]($drive.Used + $drive.Free)
        $usadoBytes = [long]$drive.Used
        $libreBytes = [long]$drive.Free

        $pctUso = if ($totalBytes -gt 0) {
            [math]::Round(($usadoBytes / $totalBytes) * 100, 1)
        } else { 0 }

        $etiqueta = try {
            $v = Get-Volume -DriveLetter $drive.Name -ErrorAction Stop
            if ($v.FileSystemLabel) { $v.FileSystemLabel } else { "(Sin etiqueta)" }
        } catch { "(Sin etiqueta)" }

        $colorUso = if ($pctUso -ge 90) { "Red" } elseif ($pctUso -ge 70) { "Yellow" } else { "Green" }

        Write-Host ("{0,-7} {1,-22} {2,-22} {3,-22} {4,-22} " -f `
            "$($drive.Name):\",
            $etiqueta,
            $totalBytes.ToString(),
            $libreBytes.ToString(),
            $usadoBytes.ToString()) -NoNewline
        Write-Host ("{0}" -f "$pctUso%") -ForegroundColor $colorUso

        $totalAcum += $totalBytes
        $libreAcum += $libreBytes
    }

    Write-Separator
    Write-Host ""

    Write-Host "  Discos fisicos detectados en el sistema:" -ForegroundColor White
    Write-Host ""
    Write-Host ("  {0,-42} {1,-22} {2,-15} {3}" -f "MODELO", "TAMANO (bytes)", "INTERFAZ", "ESTADO") -ForegroundColor White

    try {
        $discos = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop
        foreach ($d in $discos) {
            $sizeFmt  = if ($d.Size)          { [long]$d.Size }    else { "N/A" }
            $modelo   = if ($d.Model)         { $d.Model }         else { "Desconocido" }
            $interfaz = if ($d.InterfaceType) { $d.InterfaceType } else { "?" }
            $status   = if ($d.Status)        { $d.Status }        else { "?" }
            $colorSt  = if ($status -eq "OK") { "Green" } else { "Yellow" }

            Write-Host ("  {0,-42} {1,-22} {2,-15} " -f $modelo, $sizeFmt, $interfaz) -NoNewline
            Write-Host $status -ForegroundColor $colorSt
        }
    } catch {
        Write-Host "  No se pudo obtener informacion de discos fisicos." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Separator
    Write-Host "  Resumen global de almacenamiento:" -ForegroundColor White

    if ($totalAcum -gt 0) {
        $totalGB = [math]::Round($totalAcum / 1GB, 2)
        $libreGB = [math]::Round($libreAcum / 1GB, 2)
        $usadoGB = [math]::Round(($totalAcum - $libreAcum) / 1GB, 2)

        Write-Host ("  Almacenamiento total : {0} bytes  (aprox. {1} GB)" -f $totalAcum, $totalGB) -ForegroundColor Cyan
        Write-Host ("  Espacio libre total  : {0} bytes  (aprox. {1} GB)" -f $libreAcum, $libreGB) -ForegroundColor Green
        Write-Host ("  Espacio usado total  : {0} bytes  (aprox. {1} GB)" -f ($totalAcum - $libreAcum), $usadoGB) -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  Leyenda: " -NoNewline
    Write-Host "Verde" -NoNewline -ForegroundColor Green
    Write-Host " < 70%  |  " -NoNewline
    Write-Host "Amarillo" -NoNewline -ForegroundColor Yellow
    Write-Host " 70-89%  |  " -NoNewline
    Write-Host "Rojo" -NoNewline -ForegroundColor Red
    Write-Host " >= 90%"
    Write-Host ""
}

# =============================================================================
# MENU PRINCIPAL
# =============================================================================
function Show-Menu {
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host ("=" * 56) -ForegroundColor Cyan
        Write-Host "  ADMINISTRACION DE DATA CENTER -- PowerShell" -ForegroundColor Cyan
        Write-Host "  Integrante 1: Gestion de Usuarios y Discos" -ForegroundColor Cyan
        Write-Host ("=" * 56) -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  1. Usuarios del sistema y ultimo inicio de sesion" -ForegroundColor White
        Write-Host "  2. Filesystems / Discos conectados (espacio en bytes)" -ForegroundColor White
        Write-Host "  0. Salir" -ForegroundColor White
        Write-Host ""
        Write-Separator
        $opcion = Read-Host "  Seleccione una opcion [0-2]"

        switch ($opcion) {
            "1" {
                Show-Usuarios
                Read-Host "  Presione ENTER para continuar..."
            }
            "2" {
                Show-Filesystems
                Read-Host "  Presione ENTER para continuar..."
            }
            "0" {
                Write-Host ""
                Write-Host "  Hasta luego!" -ForegroundColor Green
                Write-Host ""
                return
            }
            default {
                Write-Host ""
                Write-Host "  Opcion invalida. Intente de nuevo." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
}

Show-Menu