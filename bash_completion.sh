# Debian GNU/Linux rpa completion
# Made for "rpa (rpa-base 0.2.2-6) RPA 0.0"
# Copyright 2004 Brian Schröder <mail brian-schroeder.de>
# See http://ruby.brian-schroeder.de/ for the latest version.
# License: GNU LGPL v2 or later

_rpa() {
    local cur prev cmd idx

    COMPREPLY=()
    cur=${COMP_WORDS[COMP_CWORD]}

    RPA_SIMPLE_COMMANDS=(dist list update rollback clean help)
    RPA_LOCAL_PORT_COMMANDS=(remove info check)
    RPA_REMOTE_PORT_COMMANDS=(install build source query search)
    RPA_PORT_COMMANDS=(${RPA_LOCAL_PORT_COMMANDS[*]} ${RPA_REMOTE_PORT_COMMANDS[*]})
    RPA_OPTIONS=(-h --help --no-proxy --proxy -q --quiet -x --extended \
                 --verbose --debug -v --version \
                 -f --force -p --parallelize --no-tests -r --requires \
                 -c --classification -e -eval -D --eval-display)

    idx=1
    while [ $idx -lt $COMP_CWORD ]; do
        case "${COMP_WORDS[idx]}" in
        -*) ;;
        *) prev="${COMP_WORDS[idx]}"; break;;
        esac
        idx=$[idx+1]
    done
    if [ ${prev+set} ]; then
        case " ${RPA_SIMPLE_COMMANDS[*]} " in
        *" $prev "*)
            COMPREPLY=( $(compgen -W "${RPA_OPTIONS[*]}" ${cur}) );
            return 0;;
        esac
        case " ${RPA_LOCAL_PORT_COMMANDS[*]} " in
        *" $prev "*)
            cmd=list;;
        esac
        case " ${RPA_REMOTE_PORT_COMMANDS[*]} " in
        *" $prev "*)
            cmd=query;;
        esac
        if [ "$cmd" ]; then
            COMPREPLY=( $(compgen -W "$(rpa $cmd | ruby -n -e 'puts $1 if /([-\w]+)\s+[0-9]+/')" ${cur} ) )
        else
            COMPREPLY=( $(compgen -W "${RPA_SIMPLE_COMMANDS[*]} ${RPA_PORT_COMMANDS[*]} ${RPA_OPTIONS[*]}" ${cur} ) )
        fi
    fi

    return 0
}
complete -F _rpa rpa

# 10/11/2004: First release
# 10/12/2004: Patch by Mauricio Fernández
# 19/10/2004: Rewritten by Nobu Nakada
