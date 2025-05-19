import sys
import os
import json
import subprocess
from datetime import datetime
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                           QHBoxLayout, QLabel, QLineEdit, QPushButton, 
                           QSpinBox, QComboBox, QTextEdit, QProgressBar,
                           QSlider, QCheckBox, QFileDialog, QMessageBox)
from PyQt5.QtCore import Qt, QThread, pyqtSignal
from PyQt5.QtGui import QPalette, QColor
import qdarkstyle

class ScanThread(QThread):
    progress = pyqtSignal(str)
    finished = pyqtSignal(dict)
    error = pyqtSignal(str)

    def __init__(self, target, port_range, timeout, parallel, json_output):
        super().__init__()
        self.target = target
        self.port_range = port_range
        self.timeout = timeout
        self.parallel = parallel
        self.json_output = json_output
        self.process = None

    def run(self):
        try:
            script_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'Scanzy.sh')
            cmd = [
                'bash', script_path,
                self.target,
                self.port_range,
                '--timeout', str(self.timeout),
                '--parallel', str(self.parallel)
            ]
            
            if self.json_output:
                cmd.append('--json')

            self.process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True
            )

            while True:
                output = self.process.stdout.readline()
                if output == '' and self.process.poll() is not None:
                    break
                if output:
                    self.progress.emit(output.strip())

            if self.process.returncode == 0:
                if self.json_output:
                    result = ''.join(self.process.stdout.readlines())
                    try:
                        self.finished.emit(json.loads(result))
                    except json.JSONDecodeError:
                        self.error.emit("Failed to parse JSON output")
                else:
                    self.finished.emit({})
            else:
                error = self.process.stderr.read()
                self.error.emit(error)

        except Exception as e:
            self.error.emit(str(e))

    def stop(self):
        if self.process:
            self.process.terminate()

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.scan_thread = None
        self.initUI()

    def initUI(self):
        self.setWindowTitle('Scanzy - TCP Port Scanner')
        self.setMinimumSize(800, 600)

        # Main widget and layout
        main_widget = QWidget()
        self.setCentralWidget(main_widget)
        layout = QVBoxLayout(main_widget)

        # Input section
        input_group = QWidget()
        input_layout = QVBoxLayout(input_group)

        # Target input
        target_layout = QHBoxLayout()
        target_label = QLabel('Target:')
        self.target_input = QLineEdit()
        self.target_input.setPlaceholderText('Enter hostname or IP (e.g., example.com)')
        target_layout.addWidget(target_label)
        target_layout.addWidget(self.target_input)
        input_layout.addLayout(target_layout)

        # Port range section
        port_layout = QHBoxLayout()
        port_label = QLabel('Port Range:')
        self.port_combo = QComboBox()
        self.port_combo.addItems(['Common Ports (1-1024)', 'All Ports (1-65535)', 'Custom Range'])
        self.port_input = QLineEdit()
        self.port_input.setPlaceholderText('Custom range (e.g., 80-443)')
        self.port_input.setVisible(False)
        port_layout.addWidget(port_label)
        port_layout.addWidget(self.port_combo)
        port_layout.addWidget(self.port_input)
        input_layout.addLayout(port_layout)

        # Settings section
        settings_layout = QHBoxLayout()
        
        # Timeout setting
        timeout_layout = QVBoxLayout()
        timeout_label = QLabel('Timeout (seconds):')
        self.timeout_spin = QSpinBox()
        self.timeout_spin.setRange(1, 10)
        self.timeout_spin.setValue(1)
        timeout_layout.addWidget(timeout_label)
        timeout_layout.addWidget(self.timeout_spin)
        settings_layout.addLayout(timeout_layout)

        # Parallel jobs setting
        parallel_layout = QVBoxLayout()
        parallel_label = QLabel('Parallel Jobs:')
        self.parallel_spin = QSpinBox()
        self.parallel_spin.setRange(1, 100)
        self.parallel_spin.setValue(10)
        parallel_layout.addWidget(parallel_label)
        parallel_layout.addWidget(self.parallel_spin)
        settings_layout.addLayout(parallel_layout)

        # JSON output toggle
        json_layout = QVBoxLayout()
        self.json_check = QCheckBox('JSON Output')
        json_layout.addWidget(self.json_check)
        settings_layout.addLayout(json_layout)

        input_layout.addLayout(settings_layout)

        # Control buttons
        button_layout = QHBoxLayout()
        self.scan_button = QPushButton('Start Scan')
        self.scan_button.clicked.connect(self.toggle_scan)
        self.export_button = QPushButton('Export Results')
        self.export_button.clicked.connect(self.export_results)
        self.export_button.setEnabled(False)
        button_layout.addWidget(self.scan_button)
        button_layout.addWidget(self.export_button)
        input_layout.addLayout(button_layout)

        layout.addWidget(input_group)

        # Progress bar
        self.progress_bar = QProgressBar()
        self.progress_bar.setTextVisible(False)
        self.progress_bar.setVisible(False)
        layout.addWidget(self.progress_bar)

        # Output section
        self.output_text = QTextEdit()
        self.output_text.setReadOnly(True)
        layout.addWidget(self.output_text)

        # Theme toggle
        theme_button = QPushButton('Toggle Theme')
        theme_button.clicked.connect(self.toggle_theme)
        layout.addWidget(theme_button)

        # Connect signals
        self.port_combo.currentTextChanged.connect(self.on_port_selection_changed)
        
        # Set dark theme by default
        self.dark_theme = True
        self.apply_theme()

        self.scan_results = None

    def on_port_selection_changed(self, text):
        self.port_input.setVisible(text == 'Custom Range')

    def toggle_theme(self):
        self.dark_theme = not self.dark_theme
        self.apply_theme()

    def apply_theme(self):
        if self.dark_theme:
            self.setStyleSheet(qdarkstyle.load_stylesheet_pyqt5())
        else:
            self.setStyleSheet('')

    def toggle_scan(self):
        if self.scan_thread and self.scan_thread.isRunning():
            self.scan_thread.stop()
            self.scan_button.setText('Start Scan')
            self.progress_bar.setVisible(False)
        else:
            self.start_scan()

    def start_scan(self):
        target = self.target_input.text().strip()
        if not target:
            QMessageBox.warning(self, 'Error', 'Please enter a target hostname or IP')
            return

        port_selection = self.port_combo.currentText()
        if port_selection == 'Common Ports (1-1024)':
            port_range = '1-1024'
        elif port_selection == 'All Ports (1-65535)':
            port_range = '1-65535'
        else:
            port_range = self.port_input.text().strip()
            if not port_range:
                QMessageBox.warning(self, 'Error', 'Please enter a custom port range')
                return

        self.output_text.clear()
        self.scan_button.setText('Stop Scan')
        self.export_button.setEnabled(False)
        self.progress_bar.setVisible(True)
        self.progress_bar.setRange(0, 0)

        self.scan_thread = ScanThread(
            target,
            port_range,
            self.timeout_spin.value(),
            self.parallel_spin.value(),
            self.json_check.isChecked()
        )
        self.scan_thread.progress.connect(self.update_output)
        self.scan_thread.finished.connect(self.scan_completed)
        self.scan_thread.error.connect(self.scan_error)
        self.scan_thread.start()

    def update_output(self, text):
        self.output_text.append(text)

    def scan_completed(self, results):
        self.scan_results = results
        self.scan_button.setText('Start Scan')
        self.progress_bar.setVisible(False)
        self.export_button.setEnabled(True)
        self.update_output("\nScan completed successfully!")

    def scan_error(self, error):
        self.scan_button.setText('Start Scan')
        self.progress_bar.setVisible(False)
        QMessageBox.critical(self, 'Error', f'Scan failed: {error}')

    def export_results(self):
        filename, _ = QFileDialog.getSaveFileName(
            self,
            'Export Results',
            f'scanzy_results_{datetime.now().strftime("%Y%m%d_%H%M%S")}',
            'Text Files (*.txt);;JSON Files (*.json)'
        )
        if filename:
            try:
                with open(filename, 'w') as f:
                    if filename.endswith('.json'):
                        json.dump(self.scan_results, f, indent=2)
                    else:
                        f.write(self.output_text.toPlainText())
                QMessageBox.information(self, 'Success', 'Results exported successfully!')
            except Exception as e:
                QMessageBox.critical(self, 'Error', f'Failed to export results: {str(e)}')

def main():
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec_())

if __name__ == '__main__':
    main()