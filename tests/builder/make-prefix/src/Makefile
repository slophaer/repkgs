PREFIX ?= /usr/local

all: hello

hello: hello.c
	$(CC) hello.c -o hello

install: hello
	install -D hello $(DESTDIR)$(PREFIX)/bin/hello
	install -D -m 644 configured-prefix $(DESTDIR)$(PREFIX)/share/hello/configured-prefix
	install -D -m 644 hello.conf $(DESTDIR)/etc/hello/hello.conf
	mkdir -p $(DESTDIR)/var/lib/hello
	touch $(DESTDIR)/var/lib/hello/state
