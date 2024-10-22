# Maintainer: msg
pkgname=luajit-useful
pkgver=2024.09.05.r4.b031988
pkgrel=1
pkgdesc="A luajit ffi useful library"
arch=('x86_64' 'aarch64')
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

	make PREFIX=$pkgdir install
}
