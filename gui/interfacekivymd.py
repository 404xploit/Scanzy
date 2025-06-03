""" git add .
git commit -m "feat: adicionar aplicação Scanzy para varredura de portas com KivyMD

Autor: Miranda-SJ

Descrição:
Adicionada a aplicação gráfica Scanzy, desenvolvida com KivyMD e Python, para realizar varredura de portas em hosts locais ou remotos. A interface permite que o usuário insira o host, faixa de portas, timeout e número de jobs, além de configurar opções avançadas como saída JSON e uso forçado de Netcat.

A aplicação executa um script bash (\`scanzy.sh\`) em subprocessos para realizar as varreduras, atualizando a interface com o progresso da operação. Suporta também cancelamento da varredura e cópia dos resultados para a área de transferência.

Funcionalidades:
- Entrada de parâmetros de varredura (host, portas, timeout, jobs).
- Opções avançadas: saída JSON e forçar Netcat.
- Barra de progresso da varredura.
- Exibição em tempo real dos resultados.
- Cancelamento seguro da varredura.
- Cópia dos resultados para a área de transferência.
- Log das operações em arquivo \`scanner.log\`.

Ferramentas e bibliotecas utilizadas:
- **Kivy**: para construção da interface gráfica.
- **KivyMD**: para componentes Material Design.
- **subprocess**: para execução do script externo \`scanzy.sh\`.
- **threading**: para manter a interface responsiva durante a execução do script.
- **logging**: para registro de logs das operações.
- **pathlib**: para manipulação segura de caminhos.
- **Clipboard**: para copiar resultados.
- **MDDialog, MDRaisedButton, MDProgressBar**: para UI/UX aprimorada.
- **MDExpansionPanel**: para gerenciar opções avançadas.

Melhorias adicionais:
- Inclusão de atalhos de teclado (Enter para iniciar, ESC para cancelar).
- Verificação e validação dos inputs do usuário.
- Feedback ao usuário através de toasts.
- Estilização personalizada com fonte \`BebasNeue\`.

Obs.: É necessário o arquivo \`scanzy.sh\` no mesmo diretório para funcionamento correto."
"""



# Importações padrão para manipulação de sistema, logs, subprocessos e multithreading
import os
import logging
import threading
from pathlib import Path
from subprocess import Popen, PIPE

# Importações do Kivy para interface gráfica
from kivy.clock import Clock
from kivy.core.window import Window
from kivy.core.clipboard import Clipboard
from kivy.lang import Builder
from kivy.properties import BooleanProperty, NumericProperty
from kivy.factory import Factory
from kivy.core.text import LabelBase

# Importações do KivyMD para componentes Material Design
from kivymd.app import MDApp
from kivymd.uix.dialog import MDDialog
from kivymd.uix.button import MDRaisedButton, MDFlatButton
from kivymd.toast import toast
from kivymd.uix.expansionpanel import MDExpansionPanel, MDExpansionPanelOneLine

# Configuração de logging para armazenar logs em arquivo
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    filename=os.path.join(str(Path.home()), "scanner.log"),
)
logger = logging.getLogger(__name__)

# Diretórios base e caminho para o script de varredura
BASE_DIR = Path(__file__).parent
SCANZY_SCRIPT = BASE_DIR / "scanzy.sh"

# Registro da fonte personalizada
LabelBase.register(name='BebasNeue', fn_regular='BebasNeue-Regular.ttf')

# KV Language - Definição da interface gráfica
KV = '''
# Importações internas do KV
#:import dp kivy.metrics.dp
#:import toast kivymd.toast.toast

MDScreen:
    id: scanner_screen

    # Layout principal vertical
    MDBoxLayout:
        orientation: "vertical"
        spacing: dp(10)

        # Barra superior do app
        MDTopAppBar:
            id: toolbar
            elevation: 8
            size_hint_y: None
            height: dp(56)
            right_action_items: [["help-circle-outline", lambda x: app.show_help()]]
            md_bg_color: app.theme_cls.primary_color

            MDLabel:
                text: "Scanzy"
                font_size: "28sp"
                bold: True
                theme_text_color: "Custom"
                text_color: (1, 1, 1, 1)
                halign: "center"
                valign: "center"
                size_hint_x: 1

        # Scroll principal para inputs
        ScrollView:
            bar_width: dp(10)
            bar_color: app.theme_cls.primary_color

            MDBoxLayout:
                orientation: "vertical"
                padding: [dp(20), dp(10), dp(20), dp(20)]
                spacing: dp(15)
                size_hint_y: None
                height: self.minimum_height

                # Card principal com campos de entrada
                MDCard:
                    id: main_card
                    orientation: "vertical"
                    padding: dp(20)
                    spacing: dp(15)
                    size_hint: 1, None
                    height: dp(520)
                    elevation: 10

                    # Campo: Host/IP
                    MDTextField:
                        id: host_input
                        hint_text: "Host (IP/Domínio)"
                        mode: "rectangle"
                        icon_right: "server"
                        helper_text: "Ex: 192.168.1.1 ou example.com"
                        helper_text_mode: "on_focus"
                        size_hint_y: None
                        height: dp(64)

                    # Campo: Faixa de portas
                    MDTextField:
                        id: port_range
                        hint_text: "Faixa de portas"
                        mode: "rectangle"
                        icon_right: "network"
                        helper_text: "Ex: 80,443 ou 1-1024"
                        helper_text_mode: "on_focus"
                        size_hint_y: None
                        height: dp(64)

                    # Campo: Timeout
                    MDTextField:
                        id: timeout
                        hint_text: "Timeout (segundos)"
                        mode: "rectangle"
                        input_filter: "float"
                        icon_right: "timer"
                        helper_text: "Padrão: 1s"
                        helper_text_mode: "on_focus"
                        size_hint_y: None
                        height: dp(64)

                    # Campo: Número de jobs paralelos
                    MDTextField:
                        id: jobs
                        hint_text: "Número de jobs"
                        mode: "rectangle"
                        input_filter: "int"
                        icon_right: "account-group"
                        helper_text: "Padrão: 10"
                        helper_text_mode: "on_focus"
                        size_hint_y: None
                        height: dp(64)

                    # Barra de progresso da varredura
                    MDProgressBar:
                        id: progress_bar
                        value: app.progress_value
                        max: 100
                        height: dp(8)
                        opacity: 1 if app.scanning else 0

                    # Botões principais: limpar, copiar, cancelar, iniciar
                    MDBoxLayout:
                        spacing: dp(5)
                        size_hint_y: None
                        height: dp(40)
                        padding: [0, dp(5), 0, 0]

                        MDRaisedButton:
                            text: "Limpar"
                            on_release: app.clear_output()
                            size_hint_x: 0.23
                            height: dp(40)
                            font_size: dp(12)

                        MDRaisedButton:
                            text: "Copiar"
                            on_release: app.copy_output()
                            size_hint_x: 0.23
                            height: dp(40)
                            font_size: dp(12)

                        MDRaisedButton:
                            text: "Cancelar"
                            id: cancel_button
                            disabled: not app.scanning
                            on_release: app.cancel_scan()
                            size_hint_x: 0.23
                            height: dp(40)
                            font_size: dp(12)

                        MDFloatingActionButton:
                            icon: "play"
                            on_release: app.validate_inputs()
                            disabled: app.scanning
                            size_hint_x: 0.23
                            size: dp(40), dp(40)
                            icon_size: dp(18)

                # Card de saída dos resultados
                MDCard:
                    padding: dp(10)
                    size_hint: 1, None
                    height: dp(180)
                    elevation: 10

                    MDScrollView:
                        ScanResultLabel:
                            id: result_label
                            text: "Aguardando início da varredura..."
                            markup: True
                            size_hint_y: None
                            height: self.texture_size[1]

# Componente customizado para exibir resultados
<ScanResultLabel@MDLabel>:
    size_hint_y: None
    height: self.texture_size[1]
    text_size: self.width - dp(20), None
    halign: "left"
    valign: "top"
    padding: dp(10), dp(10)
    font_style: "Caption"
    theme_text_color: "Secondary"
    canvas.before:
        Color:
            rgba: app.theme_cls.bg_darkest
        RoundedRectangle:
            pos: self.pos
            size: self.size
            radius: [10,]

# Painel de opções avançadas
<AdvancedOptions@MDBoxLayout>:
    orientation: "vertical"
    padding: dp(10)
    spacing: dp(10)
    size_hint_y: None
    height: self.minimum_height

    # Checkbox: Saída JSON
    MDBoxLayout:
        orientation: "horizontal"
        spacing: dp(10)
        size_hint_y: None
        height: dp(48)

        MDCheckbox:
            id: json_checkbox
            size_hint_x: None
            width: dp(48)

        MDLabel:
            text: "Saída JSON"
            halign: "left"
            valign: "center"

    # Checkbox: Forçar Netcat
    MDBoxLayout:
        orientation: "horizontal"
        spacing: dp(10)
        size_hint_y: None
        height: dp(48)

        MDCheckbox:
            id: netcat_checkbox
            size_hint_x: None
            width: dp(48)

        MDLabel:
            text: "Forçar Netcat"
            halign: "left"
            valign: "center"
'''

# Classe principal da aplicação
class ScannerApp(MDApp):
    scanning = BooleanProperty(False)  # Indica se a varredura está em andamento
    progress_value = NumericProperty(0)  # Valor atual da barra de progresso

    def build(self):
        # Configurações iniciais da interface
        self.theme_cls.theme_style = "Dark"
        self.theme_cls.primary_palette = "BlueGray"
        Window.bind(on_key_down=self.on_key_down)  # Atalhos de teclado
        root = Builder.load_string(KV)

        # Adiciona painel de opções avançadas dinamicamente
        advanced_options = Factory.AdvancedOptions()
        panel = MDExpansionPanel(
            icon="cog",
            content=advanced_options,
            panel_cls=MDExpansionPanelOneLine(text="Opções Avançadas"),
        )
        card = root.ids.main_card
        card.add_widget(panel, index=4)

        return root

    def on_key_down(self, window, key, *args):
        # Atalhos: Enter para iniciar, ESC para cancelar
        if key == 13:
            self.validate_inputs()
        elif key == 27:
            self.cancel_scan()

    def show_help(self):
        # Exibe diálogo de ajuda
        self.dialog = MDDialog(
            title="Ajuda",
            text="Preencha Host e Faixa de Portas.\nUse as opções avançadas conforme necessário.",
            buttons=[MDFlatButton(text="OK", on_release=lambda x: self.dialog.dismiss())]
        )
        self.dialog.open()

    def validate_inputs(self):
        # Validação dos campos antes de iniciar a varredura
        host = self.root.ids.host_input.text.strip()
        if not host:
            toast("Host é obrigatório!")
            return

        port_range = self.root.ids.port_range.text.strip()
        if port_range and not any(c.isdigit() for c in port_range):
            toast("Faixa de portas inválida!")
            return

        timeout = self.root.ids.timeout.text.strip()
        if timeout and not timeout.replace('.', '').isdigit():
            toast("Timeout inválido!")
            return

        jobs = self.root.ids.jobs.text.strip()
        if jobs and not jobs.isdigit():
            toast("Número de jobs inválido!")
            return

        self.start_scan()

    def start_scan(self):
        # Inicia a execução do scan
        if self.scanning:
            return

        # Monta o comando do script bash
        cmd = [
            "bash", str(SCANZY_SCRIPT),
            self.root.ids.host_input.text.strip(),
            self.root.ids.port_range.text.strip() or "1-1024",
            "--timeout", self.root.ids.timeout.text.strip() or "1",
            "--parallel", self.root.ids.jobs.text.strip() or "10"
        ]

        # Checa opções avançadas
        advanced_panel = [child for child in self.root.ids.main_card.children 
                         if isinstance(child, MDExpansionPanel)][0]
        advanced_options = advanced_panel.content
        if advanced_options.ids.json_checkbox.active:
            cmd.append("--json")
        if advanced_options.ids.netcat_checkbox.active:
            cmd.append("--force-netcat")

        try:
            self.prepare_scan()
            # Executa o scan em thread separada
            self.scan_thread = threading.Thread(target=self.run_scan, args=(cmd,), daemon=True)
            self.scan_thread.start()
        except Exception as e:
            self.show_error(str(e))

    def prepare_scan(self):
        # Prepara UI para o início da varredura
        self.root.ids.result_label.text = "Iniciando varredura...\n"
        self.root.ids.progress_bar.opacity = 1
        self.root.ids.cancel_button.disabled = False
        self.scanning = True
        self.progress_value = 0

    def run_scan(self, cmd):
        # Executa o comando de varredura e atualiza UI
        try:
            self.scan_process = Popen(cmd, stdout=PIPE, stderr=PIPE, universal_newlines=True)
            for line in self.scan_process.stdout:
                Clock.schedule_once(lambda dt, l=line: self.update_ui(l))
            self.scan_process.wait()
            Clock.schedule_once(lambda dt: self.complete_scan())
        except Exception as e:
            Clock.schedule_once(lambda dt: self.show_error(str(e)))

    def update_ui(self, line):
        # Atualiza o resultado na tela e a barra de progresso
        self.root.ids.result_label.text += line
        if "Progresso:" in line:
            try:
                progress = int(line.split(":")[1].strip().replace("%", ""))
                self.progress_value = progress
            except:
                pass

    def complete_scan(self):
        # Finaliza o processo de varredura
        self.scanning = False
        self.root.ids.cancel_button.disabled = True
        self.root.ids.progress_bar.opacity = 0
        toast("Varredura concluída!")

    def cancel_scan(self):
        # Cancela a varredura em andamento
        if hasattr(self, 'scan_process'):
            try:
                self.scan_process.terminate()
                self.scan_process.wait(timeout=2)
            except:
                try:
                    self.scan_process.kill()
                except:
                    pass
        self.complete_scan()
        toast("Varredura cancelada!")

    def show_error(self, message):
        # Exibe diálogo de erro
        self.dialog = MDDialog(
            title="Erro",
            text=f"Erro ao executar a varredura:\n{message}",
            buttons=[MDFlatButton(text="OK", on_release=lambda x: self.dialog.dismiss())]
        )
        self.dialog.open()
        self.complete_scan()

    def clear_output(self):
        # Limpa os resultados exibidos
        self.root.ids.result_label.text = "Aguardando início da varredura..."
        self.progress_value = 0

    def copy_output(self):
        # Copia resultados para a área de transferência
        Clipboard.copy(self.root.ids.result_label.text)
        toast("Saída copiada!")

# Executa o app
if __name__ == "__main__":
    ScannerApp().run()
