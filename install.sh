#!/usr/bin/env zsh
# Installer per zsh-infra-status (utente corrente, niente sudo).
# Idempotente: ri-eseguibile per aggiornare la copia installata.

set -e

SCRIPT_NAME="infra-status.zsh"
SRC="${0:A:h}/$SCRIPT_NAME"

[[ -r $SRC ]] || { print -u2 "errore: $SRC non trovato"; exit 1; }

# Scegli la destinazione: Oh My Zsh se presente, altrimenti ~/.config/zsh
if [[ -d ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom} ]]; then
    DST_DIR=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
    SRC_LINE='source "$ZSH_CUSTOM/'$SCRIPT_NAME'"'
else
    DST_DIR=$HOME/.config/zsh
    mkdir -p $DST_DIR
    SRC_LINE="source \"$DST_DIR/$SCRIPT_NAME\""
fi
DST=$DST_DIR/$SCRIPT_NAME

if [[ -f $DST ]] && cmp -s "$SRC" "$DST"; then
    print "[=] $DST già aggiornato"
else
    cp "$SRC" "$DST"
    print "[+] installato $DST"
fi

RC=$HOME/.zshrc
if [[ -f $RC ]] && grep -qF "$SCRIPT_NAME" "$RC"; then
    print "[=] $RC già fa source del plugin"
else
    {
        print ""
        print "# zsh-infra-status"
        print "$SRC_LINE"
    } >> "$RC"
    print "[+] aggiunto sourcing a $RC"
fi

print ""
print "Fatto. Apri una nuova shell o esegui:  source ~/.zshrc"
