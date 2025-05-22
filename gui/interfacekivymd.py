import os
import json
import logging
from subprocess import Popen, PIPE
from kivy.clock import Clock
from kivy.core.window import Window
from kivy.lang import Builder
from kivy.properties import BooleanProperty, NumericProperty, StringProperty
from kivymd.app import MDApp
from kivymd.uix.dialog import MDDialog
from kivymd.uix.button import MDRaisedButton
from kivymd.uix.menu import MDDropdownMenu
from kivymd.toast import toast
from kivymd.uix.toolbar import MDTopAppBar
from kivymd.uix.progressbar import MDProgressBar
from kivymd.uix.snackbar import Snackbar
from kivymd.uix.spinner import MDSpinner
from kivymd.uix.textfield import MDTextField
from kivymd.uix.label import MDLabel
from kivymd.uix.selectioncontrol import MDSwitch
from kivymd.uix.card import MDCard
from kivymd.uix.scrollview import MDScrollView
from kivymd.uix.boxlayout import MDBoxLayout

# Configuração de logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    filename="scanner.log",
)
logger = logging.getLogger(__name__)

KV = """
#:kivy 2.0.0
#:import toast kivymd.toast.toast

<ScanResultLabel@MDLabel>:
    size_hint_y: None
    height: self.texture_size[1]
    text_size: self.width, None
    halign: "left"
    valign: "top"
    padding: dp(10), dp(10)

MDScreen:
    name: "scanner_screen"
    
    MDTopAppBar:
        title: "Scanzy"
        pos_hint: {"top": 1}
        elevation: 8
        right_action_items: [["help-circle-outline", lambda x: toast("Ajuda: Preencha os campos e clique em Scan")]]
    
    MDBoxLayout:
        orientation: "vertical"
        padding: dp(10)
        spacing: dp(10)
        pos_hint: {"top": 0.9}

        MDCard:
            orientation: "vertical"
            padding: dp(20)
            spacing: dp(10)
            size_hint: None, None
            size: root.width - dp(20), root.height * 0.9
            pos_hint: {"center_x": 0.5}
            elevation: 10
            md_bg_color: app.theme_cls.bg_dark

            MDGridLayout:
                cols: 2
                spacing: dp(10)
                adaptive_height: True

                MDTextField:
                    id: host_input
                    hint_text: "Host (IP/Domínio)"
                    mode: "rectangle"
                    icon_right: "server"
                    helper_text: "Ex: 192.168.1.1 ou example.com"
                    helper_text_mode: "on_focus"

                MDTextField:
                    id: port_range
                    hint_text: "Faixa de portas"
                    mode: "rectangle"
                    icon_right: "network"
                    helper_text: "Ex: 80,443 ou 1-1024"
                    helper_text_mode: "on_focus"

                MDTextField:
                    id: timeout
                    hint_text: "Timeout (segundos)"
                    mode: "rectangle"
                    input_filter: "float"
                    icon_right: "timer"
                    helper_text: "Tempo de espera por porta"
                    helper_text_mode: "on_focus"

                MDTextField:
                    id: jobs
                    hint_text: "Número de jobs"
                    mode: "rectangle"
                    input_filter: "int"
                    icon_right: "account-group"
                    helper_text: "Processos paralelos"
                    helper_text_mode: "on_focus"

            MDCard:
                padding: dp(5)
                spacing: dp(5)
                size_hint_x: 1
                size_hint_y: None
                height: dp(60)  # Levemente maior para o novo layout
                md_bg_color: app.theme_cls.bg_darkest

                MDGridLayout:
                    cols: 2
                    spacing: dp(10)
                    size_hint_y: None
                    height: dp(60)

                    MDBoxLayout:
                        orientation: "horizontal"
                        spacing: dp(15)
                        size_hint_x: 0.1
                        MDLabel:
                            text: "Saída JSON"
                            halign: "left"
                            valign: "middle"
                        MDSwitch:
                            id: json_switch
                            active: False
                            size_hint: None, None
                            size: dp(45), dp(29)

                    MDBoxLayout:
                        orientation: "horizontal"
                        spacing: dp(15)
                        size_hint_x: 0.1
                        MDLabel:
                            text: "Forçar Netcat"
                            halign: "left"
                            valign: "middle"
                        MDSwitch:
                            id: netcat_switch
                            active: False
                            size_hint: None, None
                            size: dp(45), dp(29)

            MDBoxLayout:
                spacing: dp(10)
                size_hint_y: None
                height: self.minimum_height
                pos_hint: {"center_x": 0.5}

                MDRaisedButton:
                    text: "Limpar"
                    icon: "broom"
                    on_release: app.clear_output()

                MDRaisedButton:
                    text: "Copiar"
                    icon: "content-copy"
                    on_release: app.copy_output()

                MDFloatingActionButton:
                    id: scan_button
                    icon: "play"
                    md_bg_color: app.theme_cls.primary_color
                    on_release: app.confirm_scan()

                MDRaisedButton:
                    id: cancel_button
                    text: "Cancelar"
                    icon: "stop"
                    disabled: True
                    on_release: app.cancel_scan()

            MDScrollView:
                ScanResultLabel:
                    id: result_label
                    text: "Resultado aparecerá aqui..."
"""


class ScannerApp(MDApp):
    scanning = BooleanProperty(False)
    progress_value = NumericProperty(0)
    elapsed_time = StringProperty("00:00")

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.scan_process = None
        self.theme_cls.theme_style = "Dark"
        self.theme_cls.primary_palette = "BlueGray"
        Window.size = (450, 700)

    def build(self):
        return Builder.load_string(KV)

    def show_snackbar(self, text):
        Snackbar(text=text).open()

    def clear_output(self):
        self.root.ids.result_label.text = "Resultado aparecerá aqui..."
        self.progress_value = 0

    def confirm_scan(self):
        self.start_scan()

    def start_scan(self):
        if self.scanning:
            toast("Varredura já em andamento!")
            return

        host = self.root.ids.host_input.text.strip()
        ports = self.root.ids.port_range.text.strip() or "1-1024"

        cmd = ["bash", "scanner.py", host, "--ports", ports]
        try:
            self.scan_process = Popen(cmd, stdout=PIPE, stderr=PIPE)
            self.schedule_event = Clock.schedule_interval(self.update_scan_progress, 0.5)
        except Exception as e:
            self.show_snackbar(f"Erro ao iniciar scan: {str(e)}")

    def update_scan_progress(self, dt):
        if self.scan_process.poll() is not None:
            Clock.unschedule(self.schedule_event)
            self.finalize_scan()

    def finalize_scan(self):
        output, error = self.scan_process.communicate()
        if output:
            self.root.ids.result_label.text = output.decode().strip()
        toast("Varredura concluída!")

    def cancel_scan(self):
        if self.scan_process and self.scan_process.poll() is None:
            self.scan_process.terminate()
            toast("Varredura cancelada!")
        self.scanning = False

if __name__ == "__main__":
    ScannerApp().run()
