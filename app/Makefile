.PHONY: deps icon run build clean

deps:
	python -m pip install --upgrade pip
	python -m pip install PySide6 PySide6-Addons pyinstaller Pillow

icon:
	python build_exe_icon.py

run:
	python main.py

# Имя exe, ico и URL задаются в app_manifest.json; PyInstaller читает app.spec.
build: icon
	pyinstaller --noconfirm app.spec

clean:
	rm -rf build dist __pycache__
