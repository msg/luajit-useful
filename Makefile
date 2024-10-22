
override CFLAGS+=-I/usr/include/luajit-2.1 -fPIC -Wall -Wextra
override LDFLAGS+=-lpthread
lmod = `pkg-config --variable=INSTALL_LMOD luajit`
cmod = `pkg-config --variable=INSTALL_CMOD luajit`

all:

install: useful/threadingc.so
	for file in `find useful -name '*.lua'`; do \
		/bin/install -v -D -m644 $$file $(PREFIX)$(lmod)/$$file; \
	done
	for file in `find useful -name '*.so'`; do \
		/bin/install -v -D -m644 $$file $(PREFIX)$(cmod)/$$file; \
	done

useful/threadingc.so: threadingc.c
	gcc $(CFLAGS) $(LDFLAGS) -shared -o $@ $+

clean:
	rm -f useful/*.so
