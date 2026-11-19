cmake_minimum_required(VERSION 3.20)
project(STM32C552 C)

# CLion's embedded GDB server run configuration needs a project target.
# Debugging uses the NuttX ELF in the run configuration, not this stub.
add_executable(nsh-attach tools/clion-attach-stub.c)
