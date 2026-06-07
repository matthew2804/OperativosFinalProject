#!/usr/bin/env bash
# =============================================================================
# Herramienta de Administración de Data Center — Integrante 1
# Opciones: 1) Usuarios y último login  2) Filesystems / Discos
# Compatible: Git Bash en Windows (MINGW64), WSL, Linux
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

separador() {
    echo -e "${CYAN}$(printf '─%.0s' {1..75})${RESET}"
}

# Detectar entorno
detectar_entorno() {
    local os
    os=$(uname -s 2>/dev/null)
    case "$os" in
        MINGW*|MSYS*|CYGWIN*) echo "windows_gitbash" ;;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        *) echo "unknown" ;;
    esac
}

ENTORNO=$(detectar_entorno)

# =============================================================================
# OPCIÓN 1 — Usuarios del sistema y último inicio de sesión
# =============================================================================
mostrar_usuarios() {
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}║        USUARIOS DEL SISTEMA Y ÚLTIMO INICIO DE SESIÓN           ║${RESET}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""

    if [[ "$ENTORNO" == "windows_gitbash" ]]; then
        # ── Git Bash en Windows: consultar via PowerShell ──────────────────
        echo -e "${CYAN}  Entorno detectado: Git Bash / Windows${RESET}"
        echo ""

        printf "${BOLD}%-25s %-12s %-28s${RESET}\n" "USUARIO" "ESTADO" "ÚLTIMO LOGIN"
        separador

        # Llamar PowerShell inline para obtener usuarios locales
        local ps_output
        ps_output=$(powershell.exe -NoProfile -Command "
            Get-LocalUser | ForEach-Object {
                \$login = if (\$_.LastLogon) { \$_.LastLogon.ToString('yyyy-MM-dd HH:mm:ss') } else { 'Nunca / Sin registro' }
                \$estado = if (\$_.Enabled) { 'Habilitado' } else { 'Deshabilitado' }
                Write-Output (\$_.Name + '|' + \$estado + '|' + \$login)
            }
        " 2>/dev/null)

        if [[ -z "$ps_output" ]]; then
            echo -e "  ${YELLOW}No se pudo obtener la lista de usuarios de Windows.${RESET}"
        else
            while IFS='|' read -r nombre estado login; do
                # Limpiar caracteres de retorno de carro de Windows
                nombre=$(echo "$nombre" | tr -d '\r')
                estado=$(echo "$estado" | tr -d '\r')
                login=$(echo "$login"   | tr -d '\r')
                printf "%-25s %-12s %-28s\n" "$nombre" "$estado" "$login"
            done <<< "$ps_output"
        fi

        separador

        # Sesiones activas
        echo ""
        echo -e "${BOLD}  Usuario de Windows actualmente activo:${RESET}"
        local usuario_activo
        usuario_activo=$(powershell.exe -NoProfile -Command "\$env:USERNAME" 2>/dev/null | tr -d '\r')
        echo -e "  ${GREEN}→ $usuario_activo${RESET}"

        # Historial reciente via PowerShell (Event Log)
        echo ""
        echo -e "${BOLD}  Últimos inicios de sesión (Event Log - últimos 10 días):${RESET}"
        echo ""
        printf "  ${BOLD}%-25s %-25s %-12s${RESET}\n" "USUARIO" "FECHA Y HORA" "TIPO"

        powershell.exe -NoProfile -Command "
            try {
                \$events = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4624; StartTime=(Get-Date).AddDays(-10)} -MaxEvents 20 -ErrorAction Stop |
                    Where-Object { \$_.Properties[8].Value -in @(2,10) -and \$_.Properties[5].Value -notmatch 'SISTEMA|SYSTEM|\\\$' } |
                    Select-Object -First 8
                foreach (\$e in \$events) {
                    \$tipo = if (\$e.Properties[8].Value -eq 2) { 'Interactivo' } else { 'RDP/Remoto' }
                    Write-Output ('  ' + \$e.Properties[5].Value.PadRight(25) + \$e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss').PadRight(25) + \$tipo)
                }
            } catch {
                Write-Output '  (Se requiere ejecutar PowerShell como Administrador para ver el historial)'
            }
        " 2>/dev/null | tr -d '\r'

    else
        # ── Linux / WSL ────────────────────────────────────────────────────
        echo -e "${CYAN}  Entorno detectado: Linux / WSL${RESET}"
        echo ""

        local usuarios=()
        while IFS=: read -r nombre _ uid _ _ _ shell; do
            if { [[ "$uid" -eq 0 ]] || [[ "$uid" -ge 1000 ]]; } && \
               [[ "$shell" != */nologin ]] && [[ "$shell" != */false ]]; then
                usuarios+=("$nombre")
            fi
        done < /etc/passwd

        if [[ ${#usuarios[@]} -eq 0 ]]; then
            echo -e "${YELLOW}  No se encontraron usuarios con shell interactivo.${RESET}"
            echo ""; return
        fi

        printf "${BOLD}%-20s %-30s %-20s${RESET}\n" "USUARIO" "ÚLTIMO LOGIN" "DESDE (HOST/TTY)"
        separador

        for usuario in "${usuarios[@]}"; do
            local ultimo_login
            ultimo_login=$(lastlog -u "$usuario" 2>/dev/null | tail -n 1 | awk '{
                if ($2 == "**Never" || $2 == "**Nunca") { print "Nunca ha ingresado" }
                else { for(i=3; i<=NF; i++) printf $i " " }
            }')
            local host_info
            host_info=$(last -n 1 "$usuario" 2>/dev/null | head -n 1 | awk 'NF>=3 {print $3}')
            [[ -z "$host_info" || "$host_info" == "wtmp" ]] && host_info="-"
            ultimo_login=$(echo "$ultimo_login" | sed 's/[[:space:]]*$//')
            [[ -z "$ultimo_login" ]] && ultimo_login="Sin registro"
            printf "%-20s %-30s %-20s\n" "$usuario" "$ultimo_login" "$host_info"
        done

        separador
        echo -e "\n${CYAN}  Total de usuarios: ${BOLD}${#usuarios[@]}${RESET}"
        echo ""
        echo -e "${BOLD}  Usuarios conectados AHORA:${RESET}"
        local conectados
        conectados=$(who 2>/dev/null | awk '{print "  → " $1 " (desde " $2 " el " $3 " " $4 ")"}')
        [[ -z "$conectados" ]] && echo -e "  ${YELLOW}Ningún usuario activo.${RESET}" || echo -e "${GREEN}$conectados${RESET}"
    fi

    echo ""
}

# =============================================================================
# OPCIÓN 2 — Filesystems / Discos conectados (tamaño y espacio libre en bytes)
# =============================================================================
mostrar_filesystems() {
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}║          FILESYSTEMS Y DISCOS CONECTADOS AL SISTEMA             ║${RESET}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""

    if [[ "$ENTORNO" == "windows_gitbash" ]]; then
        # ── Git Bash en Windows ────────────────────────────────────────────
        echo -e "${CYAN}  Entorno detectado: Git Bash / Windows${RESET}"
        echo ""

        printf "${BOLD}%-8s %-22s %-24s %-24s %-24s %-8s${RESET}\n" \
            "UNIDAD" "ETIQUETA" "TAMAÑO TOTAL (bytes)" "ESPACIO LIBRE (bytes)" "ESPACIO USADO (bytes)" "USO %"
        separador

        local total_acum=0 libre_acum=0

        # PowerShell devuelve datos en bytes directamente
        local ps_drives
        ps_drives=$(powershell.exe -NoProfile -Command "
            Get-PSDrive -PSProvider FileSystem |
            Where-Object { \$_.Root -match '^[A-Z]:\\\\' } |
            ForEach-Object {
                \$total = \$_.Used + \$_.Free
                \$pct   = if (\$total -gt 0) { [math]::Round((\$_.Used / \$total) * 100, 1) } else { 0 }
                \$label = try { (Get-Volume -DriveLetter \$_.Name -EA Stop).FileSystemLabel } catch { '' }
                if ([string]::IsNullOrEmpty(\$label)) { \$label = '(Sin etiqueta)' }
                Write-Output (\$_.Name + ':|\' + \$label + '|' + \$total + '|' + \$_.Free + '|' + \$_.Used + '|' + \$pct)
            }
        " 2>/dev/null)

        while IFS='|' read -r unidad etiqueta total libre usado pct; do
            unidad=$(echo "$unidad"   | tr -d '\r')
            etiqueta=$(echo "$etiqueta" | tr -d '\r')
            total=$(echo "$total"     | tr -d '\r')
            libre=$(echo "$libre"     | tr -d '\r')
            usado=$(echo "$usado"     | tr -d '\r')
            pct=$(echo "$pct"         | tr -d '\r')

            [[ -z "$total" || "$total" == "0" ]] && continue

            # Color según uso
            local color="${GREEN}"
            local pct_int="${pct%.*}"
            [[ "$pct_int" -ge 90 ]] 2>/dev/null && color="${RED}"
            [[ "$pct_int" -ge 70 && "$pct_int" -lt 90 ]] 2>/dev/null && color="${YELLOW}"

            printf "%-8s %-22s %-24s %-24s %-24s ${color}%-8s${RESET}\n" \
                "$unidad" "$etiqueta" "$total" "$libre" "$usado" "${pct}%"

            total_acum=$((total_acum + total)) 2>/dev/null
            libre_acum=$((libre_acum + libre)) 2>/dev/null
        done <<< "$ps_drives"

        separador

        # Discos físicos
        echo ""
        echo -e "${BOLD}  Discos físicos detectados:${RESET}"
        printf "  ${BOLD}%-45s %-24s %-15s${RESET}\n" "MODELO" "TAMAÑO (bytes)" "INTERFAZ"

        powershell.exe -NoProfile -Command "
            Get-CimInstance Win32_DiskDrive | ForEach-Object {
                \$size = if (\$_.Size) { \$_.Size.ToString() } else { 'N/A' }
                \$iface = if (\$_.InterfaceType) { \$_.InterfaceType } else { '?' }
                \$model = if (\$_.Model) { \$_.Model } else { 'Desconocido' }
                Write-Output ('  ' + \$model.PadRight(45) + \$size.PadRight(24) + \$iface)
            }
        " 2>/dev/null | tr -d '\r'

        # Resumen
        echo ""
        separador
        echo -e "${BOLD}  Resumen global:${RESET}"
        if [[ "$total_acum" -gt 0 ]]; then
            local total_gb libre_gb
            total_gb=$(awk "BEGIN {printf \"%.2f\", $total_acum/1073741824}")
            libre_gb=$(awk "BEGIN {printf \"%.2f\", $libre_acum/1073741824}")
            printf "  %-35s %s bytes  (≈ %s GB)\n" "Almacenamiento total:" "$total_acum" "$total_gb"
            printf "  %-35s %s bytes  (≈ %s GB)\n" "Espacio libre total:"  "$libre_acum" "$libre_gb"
        fi

    else
        # ── Linux / WSL ────────────────────────────────────────────────────
        local EXCLUIR="tmpfs|devtmpfs|udev|sysfs|proc|cgroup|overlay|squashfs|nsfs|bpf|pstore"

        printf "${BOLD}%-25s %-20s %-20s %-20s %-10s %-15s${RESET}\n" \
            'DISPOSITIVO' 'TAMAÑO TOTAL (bytes)' 'ESPACIO LIBRE (bytes)' \
            'ESPACIO USADO (bytes)' 'USO %' 'PUNTO DE MONTAJE'
        separador

        local total_acum=0 libre_acum=0

        while IFS= read -r linea; do
            local disp total libre usado pct montaje
            disp=$(echo "$linea" | awk '{print $1}')
            total=$(echo "$linea" | awk '{print $2}')
            usado=$(echo "$linea" | awk '{print $3}')
            libre=$(echo "$linea" | awk '{print $4}')
            pct=$(echo "$linea"   | awk '{print $5}')
            montaje=$(echo "$linea" | awk '{print $6}')
            echo "$disp" | grep -qE "^($EXCLUIR)" && continue

            local color="${GREEN}"
            local pct_n="${pct//%/}"
            [[ "$pct_n" -ge 90 ]] 2>/dev/null && color="${RED}"
            [[ "$pct_n" -ge 70 && "$pct_n" -lt 90 ]] 2>/dev/null && color="${YELLOW}"

            printf "%-25s %-20s %-20s %-20s ${color}%-10s${RESET} %-15s\n" \
                "$disp" "$total" "$libre" "$usado" "$pct" "$montaje"

            total_acum=$((total_acum + total))
            libre_acum=$((libre_acum + libre))
        done < <(df -B1 --output=source,size,used,avail,pcent,target 2>/dev/null | tail -n +2 | sort -k6)

        separador
        echo ""
        echo -e "${BOLD}  Resumen:${RESET}"
        local total_gb libre_gb
        total_gb=$(awk "BEGIN {printf \"%.2f\", $total_acum/1073741824}")
        libre_gb=$(awk "BEGIN {printf \"%.2f\", $libre_acum/1073741824}")
        printf "  %-35s %s bytes  (≈ %s GB)\n" "Almacenamiento total:" "$total_acum" "$total_gb"
        printf "  %-35s %s bytes  (≈ %s GB)\n" "Espacio libre total:"  "$libre_acum" "$libre_gb"
    fi

    echo ""
    echo -e "  ${YELLOW}Leyenda:${RESET} ${GREEN}Verde${RESET} < 70%  |  ${YELLOW}Amarillo${RESET} 70-89%  |  ${RED}Rojo${RESET} ≥ 90%"
    echo ""
}

# =============================================================================
# MENÚ PRINCIPAL
# =============================================================================
menu_principal() {
    while true; do
        clear
        echo ""
        echo -e "${BOLD}${CYAN}  ╔══════════════════════════════════════════════════════╗${RESET}"
        echo -e "${BOLD}${CYAN}  ║     ADMINISTRACIÓN DE DATA CENTER — BASH             ║${RESET}"
        echo -e "${BOLD}${CYAN}  ║     Integrante 1: Gestión de Usuarios y Discos       ║${RESET}"
        echo -e "${BOLD}${CYAN}  ╚══════════════════════════════════════════════════════╝${RESET}"
        echo ""
        echo -e "  ${BOLD}1.${RESET} Usuarios del sistema y último inicio de sesión"
        echo -e "  ${BOLD}2.${RESET} Filesystems / Discos conectados (tamaño y espacio libre)"
        echo -e "  ${BOLD}0.${RESET} Salir"
        echo ""
        separador
        printf "  Seleccione una opción [0-2]: "
        read -r opcion

        case "$opcion" in
            1) mostrar_usuarios;    read -rp "  Presione ENTER para continuar..." ;;
            2) mostrar_filesystems; read -rp "  Presione ENTER para continuar..." ;;
            0)
                echo ""
                echo -e "  ${GREEN}Saliendo... ¡Hasta luego!${RESET}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "\n  ${RED}Opción inválida. Intente de nuevo.${RESET}"
                sleep 1
                ;;
        esac
    done
}

menu_principal
