@echo off
rem 构建包装：修复 JDK17 在 Windows 上 PipeImpl 走 AF_UNIX 因 %TEMP% 长路径报 Invalid argument 的问题
rem 把 TEMP/TMP 重定向到短路径 C:\tmp 即可。用法：build.bat [gradle 参数]
if not exist C:\tmp mkdir C:\tmp
set TEMP=C:\tmp
set TMP=C:\tmp
set JAVA_HOME=C:\dev\jdk-17.0.19+10
set ANDROID_HOME=C:\Android
set JAVA_OPTS=-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7897 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7897
cd /d %~dp0
C:\gradle\gradle-8.6\bin\gradle.bat %*
