# Maintainer: msg
pkgname=luajit-useful
pkgver=2019.10.01.r0.48c672b
pkgrel=1
pkgdesc="A luajit ffi useful library"
arch=('any')
url="http://localhost"
license=('MIT')
groups=()
depends=('luajit' 'luajit-posix')
makedepends=('pkgconf')
provides=('luajit-useful')

pkgver() {
        cd $startdir
	printf "%s" "$(git describe --long | sed 's/\([^-]*-\)g/r\1/;s/-/./g')"
}

build() {
	cd $startdir

	make clean
	make
}

package() {
	cd $startdir

	lmod="$pkgdir$(pkg-config --variable=INSTALL_LMOD luajit)"
	for i in *.lua; do
		install -D -m644 "$i" "$lmod/useful/$i"
	done

	cmod="$pkgdir$(pkg-config --variable=INSTALL_CMOD luajit)"
	for i in $(find . -name '*.so' -type f); do
		install -D -m755 "$i" "$cmod/useful/$i"
	done
}
