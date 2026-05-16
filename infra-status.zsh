# zsh-infra-status — local infrastructure state in RPROMPT
# Providers: docker, podman, multipass, qemu/libvirt, lxc
# Refreshed in background, cached, atomic writes, single-flight via lockdir.

# ---------- configuration (set BEFORE sourcing to override) ----------

typeset -ga INFRA_STATUS_PROVIDERS
(( ${#INFRA_STATUS_PROVIDERS} )) || INFRA_STATUS_PROVIDERS=(docker podman multipass qemu lxc)

: ${INFRA_STATUS_TTL:=15}
: ${INFRA_STATUS_SEPARATOR:=" %F{240}·%f "}
: ${INFRA_STATUS_SHOW_STALE:=0}
: ${INFRA_STATUS_STALE_COLOR:=240}
: ${INFRA_STATUS_CACHE_FILE:="${XDG_RUNTIME_DIR:-/tmp}/zsh-infra-status-${USER}"}
: ${INFRA_STATUS_SYNC_REFRESH:=1}  # 1 = refresh sync mirato dopo comandi infra

# Mappa comando → provider: se vedi questi comandi in preexec, refresha quel provider.
# Estendibile dall'utente: INFRA_STATUS_CMD_MAP[mycmd]=docker (anche dopo il source).
typeset -gA INFRA_STATUS_CMD_MAP
typeset -gA _infra_cmd_defaults=(
    # CLI primarie
    docker          docker
    podman          podman
    multipass       multipass
    virsh           qemu
    virt-install    qemu
    virt-clone      qemu
    lxc             lxc
    incus           lxc
    # wrapper docker/podman comuni
    docker-compose  docker
    podman-compose  podman
    compose         docker
    dc              docker
    dco             docker
    docker-rollout  docker
    lazydocker      docker
    ctop            docker
    # task runner generici (per progetti docker-based — sovrascrivi se serve)
    make            docker
    just            docker
    task            docker
)
# Merge: default + override utente, senza perdere le entry nuove dopo un reload.
local _k
for _k in ${(k)_infra_cmd_defaults}; do
    [[ -z ${INFRA_STATUS_CMD_MAP[$_k]} ]] && INFRA_STATUS_CMD_MAP[$_k]=${_infra_cmd_defaults[$_k]}
done
unset _k

typeset -gA _infra_defaults=(
    docker_icon    '🐳'   docker_color    cyan     docker_cmd    docker
    podman_icon    '🦭'   podman_color    red      podman_cmd    podman
    multipass_icon '🔶'   multipass_color yellow   multipass_cmd multipass
    qemu_icon      '🗄️'   qemu_color      magenta  qemu_cmd      virsh
    lxc_icon       '📦'   lxc_color       blue     lxc_cmd       lxc
)

_infra_attr() {
    # Resolve attribute: INFRA_STATUS_<PROVIDER>_<ATTR> env override, else default.
    local var="INFRA_STATUS_${(U)1}_${(U)2}"
    print -r -- "${(P)var:-${_infra_defaults[${1}_${2}]}}"
}

# ---------- per-provider counters (must print a single integer) ----------

_infra_count_docker()    { docker ps -q 2>/dev/null | wc -l | tr -d ' '; }
_infra_count_podman()    { podman ps -q 2>/dev/null | wc -l | tr -d ' '; }
_infra_count_multipass() {
    multipass list --format csv 2>/dev/null \
        | awk -F, 'NR>1 && $2=="Running"' | wc -l | tr -d ' '
}
_infra_count_qemu()      {
    virsh list --state-running --name 2>/dev/null \
        | awk 'NF' | wc -l | tr -d ' '
}
_infra_count_lxc()       {
    lxc list --format csv -c ns 2>/dev/null \
        | awk -F, '$2=="RUNNING"' | wc -l | tr -d ' '
}

# ---------- cache + background refresh ----------

_INFRA_LOCK="${INFRA_STATUS_CACHE_FILE}.lock"

_infra_mtime() {
    # Portable mtime: GNU stat → BSD/macOS stat → 0
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || print 0
}

_infra_update() {
    # Args: provider names to refresh (default: all). Partial updates preserve
    # other providers' counts so we can refresh only what changed.
    local -a to_refresh
    if (( $# )); then to_refresh=("$@"); else to_refresh=($INFRA_STATUS_PROVIDERS); fi

    # mkdir is atomic across POSIX — used as a single-flight mutex.
    if ! mkdir "$_INFRA_LOCK" 2>/dev/null; then
        local age=$(( EPOCHSECONDS - $(_infra_mtime "$_INFRA_LOCK") ))
        (( age > 60 )) && rmdir "$_INFRA_LOCK" 2>/dev/null
        return
    fi
    {
        typeset -A current
        local k v
        if [[ -r $INFRA_STATUS_CACHE_FILE ]]; then
            while IFS='=' read -r k v; do current[$k]=$v; done < "$INFRA_STATUS_CACHE_FILE"
        fi
        local p cmd count
        for p in $to_refresh; do
            cmd=$(_infra_attr "$p" cmd)
            count=0
            if (( $+commands[$cmd] )) && (( $+functions[_infra_count_$p] )); then
                count=$(_infra_count_$p 2>/dev/null)
                count=${count:-0}
            fi
            current[$p]=$count
        done
        local tmp="${INFRA_STATUS_CACHE_FILE}.tmp.$$"
        : > "$tmp"
        for p in $INFRA_STATUS_PROVIDERS; do
            print -r -- "$p=${current[$p]:-0}" >> "$tmp"
        done
        mv -f "$tmp" "$INFRA_STATUS_CACHE_FILE"
    } always {
        rmdir "$_INFRA_LOCK" 2>/dev/null
    }
}

_infra_render() {
    local -a parts
    local p count icon color key val stale=0
    typeset -A counts

    if [[ -r $INFRA_STATUS_CACHE_FILE ]]; then
        while IFS='=' read -r key val; do
            counts[$key]=$val
        done < "$INFRA_STATUS_CACHE_FILE"
        (( EPOCHSECONDS - $(_infra_mtime "$INFRA_STATUS_CACHE_FILE") > INFRA_STATUS_TTL )) && stale=1
    else
        stale=1
    fi

    for p in $INFRA_STATUS_PROVIDERS; do
        count=${counts[$p]:-0}
        (( count > 0 )) || continue
        icon=$(_infra_attr "$p" icon)
        if (( stale && INFRA_STATUS_SHOW_STALE )); then
            color=$INFRA_STATUS_STALE_COLOR
        else
            color=$(_infra_attr "$p" color)
        fi
        parts+=("%F{$color}${icon} ${count}%f")
    done

    if (( ${#parts} == 0 )); then
        RPROMPT=""
        return
    fi
    local sep="$INFRA_STATUS_SEPARATOR" out="${parts[1]}" i
    for ((i=2; i<=${#parts}; i++)); do
        out+="${sep}${parts[$i]}"
    done
    RPROMPT="$out"
}

typeset -ga _INFRA_PENDING

_infra_preexec() {
    (( INFRA_STATUS_SYNC_REFRESH )) || return
    local -a words=(${(z)1})
    local idx=1 w
    # Salta prefissi tipo `sudo docker ...`, `time make ...`, `env FOO=bar docker ...`
    while (( idx <= ${#words} )); do
        w=${words[idx]}
        # Assegnazioni inline (es. DOCKER_HOST=...) — check PRIMA di :t, perché
        # :t può mangiare path-separator dentro al valore (es. tcp://x → x).
        if [[ $w == *=* && $w != /* ]]; then (( idx++ )); continue; fi
        w=${w:t}
        if [[ $w == (sudo|time|nice|nohup|exec|command|builtin|noglob|env|stdbuf|ionice|taskset) ]]; then
            (( idx++ )); continue
        fi
        break
    done
    (( idx <= ${#words} )) || return
    w=${words[idx]:t}
    local p=${INFRA_STATUS_CMD_MAP[$w]}
    [[ -n $p ]] && _INFRA_PENDING+=($p)
}

# Escape hatch pubblico: forza un refresh sincrono (tutto, o solo i provider passati).
# Uso: `infra-status-refresh` oppure `infra-status-refresh docker podman`
infra-status-refresh() { _infra_update "$@"; _infra_render; }

_infra_precmd() {
    if (( ${#_INFRA_PENDING} )); then
        # Sync, mirato: solo i provider toccati. Tipicamente <100ms ciascuno.
        _infra_update ${(u)_INFRA_PENDING}
        _INFRA_PENDING=()
    elif [[ -r $INFRA_STATUS_CACHE_FILE ]]; then
        (( EPOCHSECONDS - $(_infra_mtime "$INFRA_STATUS_CACHE_FILE") > INFRA_STATUS_TTL )) \
            && _infra_update &!
    else
        _infra_update &!
    fi
    _infra_render
}

zmodload zsh/datetime  # provides $EPOCHSECONDS
autoload -Uz add-zsh-hook
add-zsh-hook precmd  _infra_precmd
add-zsh-hook preexec _infra_preexec
