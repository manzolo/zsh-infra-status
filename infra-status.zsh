# Infrastructure status in RPROMPT
# Shows: Docker containers, Multipass VMs, QEMU/libvirt VMs
# Results are cached (TTL: 15s) and updated in background to avoid prompt slowdown

_INFRA_CACHE="/tmp/.infra_status_${USER}"
_INFRA_CACHE_TTL=15

_infra_update() {
    local docker_count=0
    local multipass_count=0
    local qemu_count=0

    docker_count=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ') || docker_count=0
    multipass_count=$(multipass list 2>/dev/null | grep -c "Running") || multipass_count=0
    qemu_count=$(virsh list --state-running 2>/dev/null | grep -c "running") || qemu_count=0

    printf '%s:%s:%s' "$docker_count" "$multipass_count" "$qemu_count" > "$_INFRA_CACHE"
}

_infra_rprompt() {
    local data docker_count multipass_count qemu_count
    local -a parts

    # Init cache on first run
    if [[ ! -f "$_INFRA_CACHE" ]]; then
        printf '0:0:0' > "$_INFRA_CACHE"
        _infra_update &!
        return
    fi

    # Trigger background refresh if cache is stale
    local now cache_time
    now=$(date +%s)
    cache_time=$(stat -c %Y "$_INFRA_CACHE" 2>/dev/null) || cache_time=0
    if (( now - cache_time > _INFRA_CACHE_TTL )); then
        _infra_update &!
    fi

    data=$(cat "$_INFRA_CACHE" 2>/dev/null) || return
    docker_count="${data%%:*}"
    local rest="${data#*:}"
    multipass_count="${rest%%:*}"
    qemu_count="${rest##*:}"

    [[ $docker_count -gt 0 ]]    && parts+=("%F{cyan}🐳 ${docker_count}%f")
    [[ $multipass_count -gt 0 ]] && parts+=("%F{yellow}🔶 ${multipass_count}%f")
    [[ $qemu_count -gt 0 ]]      && parts+=("%F{magenta}🗄️ ${qemu_count}%f")

    if (( ${#parts[@]} > 0 )); then
        local result="${parts[1]}"
        local i
        for ((i=2; i<=${#parts[@]}; i++)); do
            result+=" %F{240}·%f ${parts[$i]}"
        done
        RPROMPT="$result"
    else
        RPROMPT=""
    fi
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _infra_rprompt
