# The test prepends the seed shell's shebang. No real build system is needed.
set -eu
name=${0##*/}
case "$name:$1" in
    jig:cache)
        printf '%s\n' "$3" >> "$CACHE_KEYS"
        test "$2" != get
        exit $? ;;
    configure:*)
        printf '%s\n' "$PKGS_PREFIX" > configured-prefix
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
