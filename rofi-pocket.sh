#!/usr/bin/env sh

TAB=$'\t'

# defaults
CACHE_DIR=${XDG_CACHE_DIR:-~/.cache}/rofi-pocket
BROWSER=${BROWSER:-chromium}
REFRESH=false
STALE=false
EXIT=false

usage() {
    echo "$0 [-c CACHE_DIR] [-r]"
    echo "  -c CACHE_DIR    directory to store pockyt cache"
    echo "  -r              refresh pockyt cache"
    echo "  -x              exit before showing rofi (only makes sense with -r)"
    echo "  -s SECONDS      time in seconds before cache becomes stale"
    echo "  -h              show this help"
}

while getopts 'c:rs:xb:h' opt; do
  case "$opt" in
    c)
      CACHE_DIR="${OPTARG}"
      ;;
    r)
      REFRESH=true
      ;;
    s)
      # Compare the time x seconds ago to the mtime of the cache file
      CACHE_AGE=$(stat -c %Y "${CACHE_DIR}/pockyt.tsv")
      CUTOFF=$(( $(date +%s) - ${OPTARG} ))
      [[ ${CACHE_AGE} < ${CUTOFF} ]] && STALE=true
      ;;
    x)
      EXIT=true
      ;;
    b)
      BROWSER="${OPTARG}"
      ;;
    h)
      usage
      exit
      ;;
    ?)
      usage
      exit 1
      ;;
  esac
done
shift $(( OPTIND - 1 ))

POCKYT_CACHE="${CACHE_DIR}/pockyt.tsv"

# If cache does not exist, cache is stale, or refresh is forced
( [ ! -f "${POCKYT_CACHE}" ] || $STALE || $REFRESH ) && {
    # check if pockyt command is available
    command -v pockyt >/dev/null || {
        echo "pockyt is needed to use this script" >&2
        exit 1
    }

    # check if pocky has been authenticated
    [ ! -f ~/.pockyt ] && {
        echo "It looks like you haven't configured pockyt yet"
        exit 1
    }

    mkdir -p ${CACHE_DIR}

    # use readarray builtin to store output of pockyt into array
    readarray -t pockyt_out <<< $(pockyt get -f "{title}${TAB}{link}${TAB}{tags}")

    # pockyt output needs to be processed to handle entries with/without tags
    readarray -t pockyt_entries <<< $(
        for line in "${pockyt_out[@]}";{
            IFS=${TAB} read desc link tags <<< ${line}
            [[ "${tags}" = "None" ]] && {
                tags=''
            } || {
                tags=$(echo ${tags:12:-2}|tr -d " '")
            }
            echo "${desc}${TAB}${link}${TAB}${tags}"
        }
    )

    # output pockyt entries to cache
    printf "%s\n" "${pockyt_entries[@]}" > "${POCKYT_CACHE}"
} || {
    # read in lines from pockyt.tsv into array
    readarray -t pockyt_entries < "${POCKYT_CACHE}"
}

$EXIT && exit

# Run rofi on pockyt entries, storing the index of the chosen line
pockyt_index=$(
    for entry in "${pockyt_entries[@]}";{
        IFS=${TAB} read desc link tags <<< ${entry}
        [ ! -z "${tags}" ] && tags=" (${tags})"
        echo "${desc}${tags}"
    }|rofi -no-show-icons -p "Pocket: " -dmenu -i -format i -kb-custom-2 alt+r
)
# Keep the exit status of rofi, which can be used to determine the pressed key
exit_status=$?

case $exit_status in
    # if escape was pressed
    1)
      exit
      ;;
    # if enter was pressed
    0)
      IFS=${TAB} read desc link tags <<< ${pockyt_entries[${pockyt_index}]}
      # open link in configured browser
      ${BROWSER} "${link}"
      ;;
    # if alt+r was pressed
    11)
      # run refresh operation and open rofi again
      $0 -r
esac
