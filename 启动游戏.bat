@echo off
@chcp 65001 >NUL
title 柴火快餐
cd /d "%~dp0"

set "GAME=%~dp0builds\windows\ChaihuoFastFood.exe"
if not exist "%GAME%" (
  echo 没找到可玩包：%GAME%
  echo 让 Qoder 重跑一次导出命令后再双击这个文件。
  pause
  exit /b 1
)

start "" "%GAME%"
exit /b 0
