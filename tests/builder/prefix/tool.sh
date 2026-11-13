# The test prepends the seed shell's shebang. No real build system is needed.
set -eu
name=${0##*/}
case "$name:$1" in
    jig:cache)
        printf '%s\n' "$3" >> "$CACHE_KEYS"
        test "$2" != get
        exit $? ;;
    configure:*)
        # autotools passes the prefix through config.site, make's hand-written script the last
        # --prefix, as a real one would take it
        prefix=${PKGS_PREFIX:-}
        for arg do
            case "$arg" in --prefix=*) prefix=${arg#--prefix=} ;; esac
        done
        printf '%s\n' "$prefix" > configured-prefix
        exit 0 ;;
    meson:setup|cmake:-S)
        for arg do
            case "$arg" in
                -Dprefix=*) prefix=${arg#-Dprefix=} ;;
                -DCMAKE_INSTALL_PREFIX=*) prefix=${arg#-DCMAKE_INSTALL_PREFIX=} ;;
            esac
        done
        printf '%s\n' "$prefix" > configured-prefix
        : > CMakeCache.txt
        exit 0 ;;
    meson:install|cmake:--install|make:install) ;;
    *) echo "unexpected fixture command: $name $*" >&2; exit 1 ;;
esac
prefix=$(cat configured-prefix)
# make's command line: its PREFIX/prefix must be the configured one, DESTDIR as make would see it
for arg do
    case "$arg" in
        PREFIX=*|prefix=*)
            if test "${arg#*=}" != "$prefix"; then
                echo "make install $arg, configured $prefix" >&2
                exit 1
            fi ;;
        DESTDIR=*) DESTDIR=${arg#DESTDIR=} ;;
    esac
done
if test "${OUTSIDE_PREFIX:-0}" = 1; then
    mkdir -p "$DESTDIR/etc"
    printf 'must not disappear\n' > "$DESTDIR/etc/unexpected"
fi
if test "${STAGED:-0}" = 1; then
    mkdir -p "$DESTDIR/etc/ssh" "$DESTDIR/var/lib/fixture"
    printf 'nested root\n' > "$DESTDIR/etc/ssh/sshd_config"
    : > "$DESTDIR/var/lib/fixture/state"
fi
# Never let a broken installer write outside this test's temporary directory.
if test "$prefix" != "$TEST_OUT" && test -z "${DESTDIR:-}"; then
    echo 'missing DESTDIR for a non-scratch prefix' >&2
    exit 1
fi
for subdir in lib/pkgconfig share/pkgconfig lib/triple/pkgconfig; do
    dir="${DESTDIR:-}$prefix/$subdir"
    mkdir -p "$dir"
    printf 'prefix=%s\nlibdir=${prefix}/lib\nName: fixture\nVersion: 1\n' "$prefix" > "$dir/fixture.pc"
done
