@REM @echo off
@REM echo Deleting bin and obj folders...
@REM for /d /r . %%d in (bin,obj) do (
@REM     if exist "%%d" (
@REM         echo Deleting "%%d"
@REM         rd /s /q "%%d"
@REM     )
@REM )
@REM echo Done.
@echo off
echo Running flutter clean...
call flutter clean
echo Build and .dart_tool directories deleted.
pause
