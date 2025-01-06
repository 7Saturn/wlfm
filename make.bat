REM This expects the FreeBasic compiler to be either in the same folder of to be
REM part of the PATH variable of Windows. It also assumes you are using the DOS
REM compiler. While the program will probably work just fine under Windows or
REM Linux, it is not meant to be used in this fashion.
ECHO OFF
CLS
fbc -O 3 wlfm.bas
