
override CFLAGS+=-I/usr/include/luajit-2.1 -fPIC -Wall -Wextra
override LDFLAGS+=-lpthread
LMOD = $(PREFIX)/`pkg-config --variable=INSTALL_LMOD luajit`
CMOD = $(PREFIX)/`pkg-config --variable=INSTALL_CMOD luajit`

all: useful/threadingc.so

install: useful/threadingc.so
	for file in `find useful -name '*.lua'` useful/http/mime.types; do \
		/bin/install -D -m644 $$file $(LMOD)/$$FILE; \
	done
	for file in `find useful -name '*.so'`; do \
		/bin/install -D -m644 $$file $(CMOD)/$$FILE; \
	done

useful/threadingc.so: threadingc.c
	gcc $(CFLAGS) $(LDFLAGS) -shared -o $@ $+

clean:
	rm -f useful/*.so
