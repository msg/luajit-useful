
CFLAGS=-I/usr/include/luajit-2.1 -g

threading.so: threading.c
	gcc $(CFLAGS) -fPIC -shared -lluajit-5.1 -lpthread -o $@ $+

clean:
	rm threading.so
