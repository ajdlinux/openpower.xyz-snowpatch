/* A hack to get around limitations in docker bind mounts until we fix how we do volumes... Run setuid root */

#include <stdlib.h>
int main() { system("rm -rf tools/mysql/db/data/"); }
