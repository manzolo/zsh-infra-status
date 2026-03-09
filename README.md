# zsh-infra-status

Plugin per **Oh My Zsh** che mostra a colpo d'occhio nel prompt a destra (RPROMPT) lo stato delle infrastrutture locali:

| Indicatore | Cosa mostra |
|---|---|
| 🐳 `docker:N` | Container Docker attivi |
| 📦 `mp:N` | VM Multipass in esecuzione |
| 🖥 `vm:N` | VM QEMU/libvirt in esecuzione |

Gli indicatori appaiono solo se il contatore è maggiore di zero, quindi il prompt rimane pulito quando non c'è nulla in esecuzione.

## Requisiti

- [Oh My Zsh](https://ohmyz.sh/)
- `docker` (opzionale)
- `multipass` (opzionale)
- `virsh` / libvirt (opzionale)

## Installazione

```zsh
cp infra-status.zsh ~/.oh-my-zsh/custom/
```

Aggiungi alla fine di `~/.zshrc`:

```zsh
source "$ZSH_CUSTOM/infra-status.zsh"
```

Ricarica la shell:

```zsh
source ~/.zshrc
```

## Come funziona

- I comandi di controllo vengono eseguiti **in background** per non rallentare il prompt
- I risultati vengono salvati in una cache (`/tmp/.infra_status_<utente>`) con TTL di **15 secondi**
- Ad ogni nuovo prompt, se la cache è scaduta, viene avviato un aggiornamento in background

## Personalizzazione

Modifica `infra-status.zsh` per cambiare il TTL della cache:

```zsh
_INFRA_CACHE_TTL=15  # secondi
```
