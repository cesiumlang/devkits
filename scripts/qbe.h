/* The one entry point of libqbe.a: QBE's own main(), renamed.
 *
 * libqbe.a is QBE (https://c9x.me/compile/) built unmodified with
 * -Dmain=qbe_main, so it behaves exactly like the `qbe` program:
 *
 *   qbe_main(argc, argv)   with argv = { "qbe", "-t", "amd64_sysv",
 *                                        "-o", "out.s", "in.ssa", 0 }
 *
 * Like the program, it does not return: it calls exit(0) when done and
 * exit(1) on an error, after printing to stderr. Call it last.
 */
#ifndef QBE_H
#define QBE_H

int qbe_main(int argc, char *argv[]);

#endif
