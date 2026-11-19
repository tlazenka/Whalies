@echo off
setlocal
cd /d "%~dp0"
if not defined PYTHON set "PYTHON=python"
"%PYTHON%" "%~dp0..\python\whaley.py" sbt -- %*
exit /b %errorlevel%
