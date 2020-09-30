
CFLAGS=-I/usr/include/luajit-2.1 -g

threading.so: threading.c threading.h
	gcc $(CFLAGS) -fPIC -Wall -Wextra -shared -lluajit-5.1 -lpthread -o $@ $+

threading.h: threading.luac
	luajit -b $< $@

clean:
	rm -f threading.so threading.h
