@echo off
setlocal

set "_TEMP=_temp"
set "_OUT=_out"
set "_CARD_OUT=card"
set "_SAVE_EXT_OUT=save_ext"

if /I "%1"=="clean" (
	echo Cleaning...
	for %%f in ("%_OUT%\%_CARD_OUT%.*") do (
		del /Q "%%f" 2> nul
		del /Q "%%~dpnf.*" 2> nul
	)
	for %%f in ("%_OUT%\%_SAVE_EXT_OUT%_en.*") do (
		del /Q "%%f" 2> nul
		del /Q "%%~dpnf.*" 2> nul
	)
	for %%f in ("%_OUT%\%_SAVE_EXT_OUT%_jp.*") do (
		del /Q "%%f" 2> nul
		del /Q "%%~dpnf.*" 2> nul
	)
	rmdir /S /Q "%_TEMP%" 2> nul
	goto :done
) else if /I "%1"=="jp" (
	set "_TARGET=jp"
) else if /I "%1"=="en" (
	set "_TARGET=en"
) else if /I "%1"=="" (
	set "_TARGET=en"
) else (
	echo Unknown target %1.
	goto :error
)

if "%_TARGET%"=="en" (
	echo Building target English
	set "_GAME=MMBN4"
	set "_TEXT_FILE=kaizou_en"
) else if "%_TARGET%"=="jp" (
	echo Building target Japanese
	set "_GAME=EXE4"
	set "_TEXT_FILE=kaizou_jp"
)

mkdir "%_TEMP%" 2> nul
pushd "%_TEMP%"
rmdir /S /Q . 2> nul
popd

mkdir "%_OUT%" 2> nul

"tools\TextPet" ^
	Load-Plugins "tools\plugins" ^
	Game %_GAME% ^
	Read-Text-Archives "%_TEXT_FILE%.tpl" ^
	Write-Text-Archives "%_TEMP%\%_TEXT_FILE%.msg" ^
	|| goto :error

"tools\armips" "save_ext.asm" ^
	-strequ CARD_FILE "%_TEMP%\%_CARD_OUT%.msg" ^
	-strequ SAVE_EXT_FILE "%_TEMP%\%_SAVE_EXT_OUT%_%_TARGET%.bin" ^
	-strequ TEXT_FILE "%_TEMP%\%_TEXT_FILE%.msg" ^
	-strequ TARGET "%_TARGET%" ^
	|| goto :error

python "add_checksum.py" "%_TEMP%\%_SAVE_EXT_OUT%_%_TARGET%.bin" || goto :error

copy /Y "%_TEMP%\%_SAVE_EXT_OUT%_%_TARGET%.bin" "%_TEMP%\%_SAVE_EXT_OUT%_%_TARGET%.lz.bin" || goto :error
"tools\lzss" -ewn "%_TEMP%\%_SAVE_EXT_OUT%_%_TARGET%.lz.bin" || goto :error

copy /Y "%_TEMP%\%_CARD_OUT%.msg" "%_OUT%\%_CARD_OUT%.msg"
copy /Y "%_TEMP%\%_SAVE_EXT_OUT%_%_TARGET%.lz.bin" "%_OUT%\%_SAVE_EXT_OUT%_%_TARGET%.lz.bin"

:done
echo Done!
exit /b 0

:error
echo Error!
exit /b 1
