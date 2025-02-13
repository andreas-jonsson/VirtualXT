all: gdbstub.a

gdb.o: gdb.c gdbstub/gdbstub.h
	$(CC) -fPIC -O -c gdb.c

gdbstub.a: gdb.o
	$(AR) rcs gdbstub.a gdb.o

clean:
	rm -f gdbstub.a gdb.o
