# zsh-infra-status

Plugin per **Oh My Zsh** che mostra a colpo d'occhio nel prompt a destra (RPROMPT) lo stato delle infrastrutture locali.

| Provider  | Indicatore | Cosa mostra |
|---|---|---|
| `docker`    | 🐳 `N` | Container Docker attivi |
| `podman`    | 🦭 `N` | Container Podman attivi |
| `multipass` | 🔶 `N` | VM Multipass in esecuzione |
| `qemu`      | 🗄️ `N` | VM QEMU/libvirt in esecuzione |
| `lxc`       | 📦 `N` | Container LXC/LXD in esecuzione |

Gli indicatori attivi sono separati da `·` grigio. Esempio:

```
🐳 3 · 🦭 1 · 🔶 2 · 🗄️ 1
```

Compaiono solo se il contatore è maggiore di zero, quindi il prompt resta pulito quando non c'è nulla in esecuzione. I provider con il binario non installato vengono saltati automaticamente.

## Requisiti

- [Oh My Zsh](https://ohmyz.sh/) (o qualsiasi zsh)
- Almeno uno tra: `docker`, `podman`, `multipass`, `virsh` (libvirt), `lxc` (LXD)

## Installazione

### Veloce (consigliata)

```zsh
./install.sh
```

Lo script è idempotente: copia il plugin in `$ZSH_CUSTOM` (o `~/.config/zsh` se non usi Oh My Zsh) e aggiunge la riga di `source` a `~/.zshrc` solo se manca. Rieseguilo per aggiornare.

### Manuale

```zsh
cp infra-status.zsh ~/.oh-my-zsh/custom/
echo 'source "$ZSH_CUSTOM/infra-status.zsh"' >> ~/.zshrc
source ~/.zshrc
```

## Come funziona

- I conteggi vengono eseguiti in **background**, mai durante il rendering del prompt
- Risultato salvato in cache (`$XDG_RUNTIME_DIR/zsh-infra-status-<utente>` o `/tmp/...`) con TTL di **15s**
- Scrittura **atomica** (`mv` di un tempfile) e **single-flight** via lockdir (`mkdir`) → niente race anche con tante shell concorrenti
- Lock stale auto-recuperato dopo 60s se un processo crasha
- Provider non installati vengono saltati senza spawnare nessun processo (`$+commands[...]`)
- Compatibile **Linux e macOS** (`stat -c` con fallback `stat -f`)
- **Refresh istantaneo dopo cambi di stato:** un hook `preexec` riconosce `docker`, `podman`, `multipass`, `virsh`, `lxc`/`incus` (anche via `sudo`) e fa un refresh **mirato e sincrono** del solo provider toccato, così il prompt riflette subito start/stop senza aspettare il TTL. Disabilita con `INFRA_STATUS_SYNC_REFRESH=0`.

## Configurazione

Tutte le variabili vanno impostate **prima** di sourcerare il plugin.

### Globali

| Variabile | Default | Descrizione |
|---|---|---|
| `INFRA_STATUS_PROVIDERS` | `(docker podman multipass qemu lxc)` | Array dei provider in ordine di visualizzazione |
| `INFRA_STATUS_TTL` | `15` | TTL della cache in secondi |
| `INFRA_STATUS_SEPARATOR` | `" %F{240}·%f "` | Separatore tra indicatori (prompt-escapes ok) |
| `INFRA_STATUS_SHOW_STALE` | `0` | Se `1`, attenua i colori quando la cache è scaduta |
| `INFRA_STATUS_STALE_COLOR` | `240` | Colore usato quando stale |
| `INFRA_STATUS_CACHE_FILE` | `$XDG_RUNTIME_DIR/zsh-infra-status-$USER` | Path del file di cache |
| `INFRA_STATUS_SYNC_REFRESH` | `1` | Refresh sync mirato dopo comandi infra rilevati in `preexec` |
| `INFRA_STATUS_CMD_MAP` | vedi sotto | Associative array `comando → provider` per il refresh mirato |

### Mappa comando → provider

Default:

```
docker, docker-compose, compose, dc, dco, docker-rollout, lazydocker, ctop → docker
podman, podman-compose                                                     → podman
multipass                                                                  → multipass
virsh, virt-install, virt-clone                                            → qemu
lxc, incus                                                                 → lxc
make, just, task                                                           → docker  (override se i tuoi task runner toccano altri provider)
```

Il preexec salta automaticamente prefissi come `sudo`, `time`, `nice`, `nohup`, `env FOO=bar`, `command`, ecc., quindi `sudo docker ...` o `env DOCKER_HOST=... docker ...` vengono riconosciuti.

Per estendere (es. alias custom):

```zsh
INFRA_STATUS_CMD_MAP[mycli]=docker
INFRA_STATUS_CMD_MAP[make]=qemu   # se nei tuoi progetti `make` lancia VM libvirt
```

### Refresh manuale

```zsh
infra-status-refresh           # refresh sincrono di tutti i provider
infra-status-refresh docker    # solo docker
```

Utile come escape hatch per casi non coperti dalla mappa (es. webhook che cambia container, modifiche fatte da un'altra shell, UI esterna).

### Per provider

Override icona o colore di un provider con:

```zsh
INFRA_STATUS_<PROVIDER>_ICON="..."
INFRA_STATUS_<PROVIDER>_COLOR="..."
```

Esempio:

```zsh
INFRA_STATUS_DOCKER_ICON="D"
INFRA_STATUS_DOCKER_COLOR="blue"
INFRA_STATUS_PROVIDERS=(docker qemu)   # mostra solo questi due
source "$ZSH_CUSTOM/infra-status.zsh"
```

## Aggiungere un provider custom

Definisci una funzione `_infra_count_<nome>` che stampa un intero, dichiara i default e aggiungilo all'array:

```zsh
_infra_count_k3s() {
    kubectl get pods -A --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' '
}
INFRA_STATUS_K3S_ICON="☸"
INFRA_STATUS_K3S_COLOR="green"
INFRA_STATUS_K3S_CMD="kubectl"   # usato per il check di installazione
INFRA_STATUS_PROVIDERS+=(k3s)
```
