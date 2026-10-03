@echo off
@chcp 65001 > nul
title 柴火快餐
cd /d "%~dp0"

if not exist "%~dp0ChaihuoFastFood.exe" (
  echo 这个文件夹里没有 ChaihuoFastFood.exe，请把整包一起拷贝。
  pause
  exit /b 1
)

start "" "%~dp0ChaihuoFastFood.exe"
exit /b 0
