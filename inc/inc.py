from flask import Flask, render_template, request, redirect, url_for, flash, jsonify
from flask_socketio import SocketIO, emit
import subprocess
import os
import select
import threading
import time
import re

app = Flask(__name__)
app.secret_key = 'my_secret_key'  # Use a secure key here
socketio = SocketIO(app)

CONTROLS_SCRIPT_DIR = "/home/user/inc/controls/"
GENERAL_SETUP_DIR = "/home/user/inc/general_setup/"
SCRIPT_DIR = "/home/user/inc/"
IMAGE_PATH = "/static/style/topology.svg"
IPv4_REGEX = r"^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\." \
              r"(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\." \
              r"(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\." \
              r"(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"

def call_script(script_dir, script_name, process_type=None, *args):
    command = f"bash {script_dir}{script_name} {' '.join(map(str, args))}"
    print(f"Executing command: {command}")  # Debug output

    env = os.environ.copy()
    env["ANSIBLE_FORCE_COLOR"] = "true"

    # Keywords-list of ansible warnings to be ignored
    ignore_keywords = ["interpreter", "ansible", "python", "idempotency", "configuration", "device"]

    try:
        with subprocess.Popen(command, shell=True, executable="/bin/bash",
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, env=env, bufsize=1) as process:
            while True:
                reads = [process.stdout.fileno(), process.stderr.fileno()]
                ret = select.select(reads, [], [])
                # Real-time output of stdout (download status)
                if process.stdout.fileno() in ret[0]:
                    line = process.stdout.readline()
                    if line:
                        print(line, end='', flush=True)  # Real-time output of stdout
                # Filter and hide warnings based on keywords
                if process.stderr.fileno() in ret[0]:
                    line = process.stderr.readline()
                    if line:
                        # Ignore if any of the ignore keywords are found in the line
                        if not any(keyword in line.lower() for keyword in ignore_keywords):
                            print(line, end='', flush=True)  # Show other errors immediately
                # Terminate when the process is complete
                if process.poll() is not None:
                    break
            # Wait until the process is fully completed
            process.wait()

            if process.returncode == 0:
                if process_type == "toggle_mode":
                    pass
                else:
                    flash(f"Script {script_name} executed successfully!", "success")
            else:
                flash(f"Script {script_name} failed with exit code {process.returncode}.", "error")

    except FileNotFoundError:
        flash(f"Script {script_name} not found or invalid command!", "error")
        print(f"Script {script_name} not found or invalid command!")

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/toggle_mode', methods=['POST'])
def toggle_mode():
    mode = request.json.get("mode")
    call_script(SCRIPT_DIR, "toggle_mode.sh", "toggle_mode", mode)
    return '', 204

@app.route('/general_setup', methods=['GET', 'POST'])
def general_setup():
    if request.method == 'POST':
        errors = []
        if 'create_pfsense' in request.form:
            pfs_node_no = request.form.get("pfs_node_no", "").strip()
            pfs_iso_name = request.form.get("pfs_iso_name", "").strip()
            
            if not pfs_node_no or not pfs_iso_name:
                errors.append("At least one field was left empty!")
            elif not pfs_node_no.isdigit():
                errors.append("The PVE Node No must be a digit!")

            if errors:
                for error in errors:
                    flash(error, "error")
                return redirect(url_for('general_setup'))

            args = [pfs_node_no, pfs_iso_name]
            call_script(GENERAL_SETUP_DIR, 'pfsense.sh', "create_pfsense", *args)

        elif 'postinstall_pfsense' in request.form:
            pfs_postinstall_node_no = request.form.get("pfs_postinstall_node_no", "").strip()
            node_arrangement = request.form.get("NodeArrangement", "cluster").strip()         
            
            if not pfs_postinstall_node_no or not node_arrangement:
                errors.append("At least one field was left empty!")
            elif not pfs_postinstall_node_no.isdigit():
                errors.append("The PVE Node No must be a digit!")

            if errors:
                for error in errors:
                    flash(error, "error")
                return redirect(url_for('general_setup'))

            args = [pfs_postinstall_node_no, node_arrangement]
            call_script(GENERAL_SETUP_DIR, 'pfs_postinstall.sh', "postinstall_pfsense", *args)

        elif 'create_dhcp_server' in request.form:
            dhcp_node_no = request.form.get("dhcp_node_no", "").strip()
            dhcp_iso_name = request.form.get("dhcp_iso_name", "").strip()
            
            if not dhcp_node_no or not dhcp_iso_name:
                errors.append("At least one field was left empty!")
            elif not dhcp_node_no.isdigit():
                errors.append("The PVE Node No must be a digit!")

            if errors:
                for error in errors:
                    flash(error, "error")
                return redirect(url_for('general_setup'))

            args = [dhcp_node_no, dhcp_iso_name]
            call_script(GENERAL_SETUP_DIR, 'dhcp.sh', "create_dhcp_server", *args)

        elif 'postinstall_and_configure_dhcp_server' in request.form:
            dhcp_server_ip = request.form.get("dhcp_server_ip", "").strip()
            dhcp_username = request.form.get("dhcp_username", "").strip()
            dhcp_user_password = request.form.get("dhcp_user_password", "").strip()
            pve_user_password = request.form.get("pve_user_password", "").strip()
                        
            if not dhcp_server_ip or not dhcp_username or not dhcp_user_password or not pve_user_password:
                errors.append("The field PVE IP (v4) was left empty!")
            elif not re.match(IPv4_REGEX, dhcp_server_ip):
                errors.append("Invalid DHCP Server IP address!")

            if errors:
                for error in errors:
                    flash(error, "error")
                return redirect(url_for('general_setup'))

            args = [dhcp_server_ip, dhcp_username, dhcp_user_password, pve_user_password]
            call_script(GENERAL_SETUP_DIR, 'dhcp_postinstall_configure.sh', "postinstall_and_configure_dhcp_server", *args)

        return redirect(url_for('general_setup'))
    return render_template('general_setup.html')

@app.route('/vyos_setup', methods=['GET', 'POST'])
def vyos_setup():
    if request.method == 'POST':
        errors = []
        if 'create_seed' in request.form:
            call_script(SCRIPT_DIR, 'seed.sh', "create_seed")

        elif 'create_vyos_qcow2' in request.form:
            vm_username = request.form.get("VM_Username", "").strip()
            vm_ip = request.form.get("VM_IP", "").strip()
            version_no = request.form.get("VersionNo", "").strip()
            
            if not vm_username or not vm_ip or not version_no:
                errors.append("At least one field was left empty!")
            elif not re.match(IPv4_REGEX, vm_ip):
                errors.append("Invalid VM IP address!")
            
            if errors:
                for error in errors:
                    flash(error, "error")
                return redirect(url_for('vyos_setup'))

            args = [vm_username, vm_ip, version_no]
            call_script(SCRIPT_DIR, 'start_vyos_qcow2.sh', "create_vyos_qcow2", *args)

        return redirect(url_for('vyos_setup'))
    return render_template('vyos_setup.html')

@app.route('/creator', methods=['GET', 'POST'])
def creator():
    if request.method == 'POST':
        errors = []
        provider = request.form.get("Provider", "").strip()
        first_router = request.form.get("FirstRouter", "").strip()
        last_router = request.form.get("LastRouter", "").strip()
        start_delay = request.form.get("StartDelay", "").strip()
        release_type = request.form.get("ReleaseType", "stream").strip()
        major_version_no = request.form.get("MajorVersionNo", "").strip()
        admin_password = request.form.get("AdminPassword", "").strip()

        if not provider or not first_router or not last_router or 'vyos' in request.form and not start_delay or 'mtk' in request.form and (not major_version_no or not admin_password):
            errors.append("At least one field was left empty!")
        elif not provider.isdigit() or not first_router.isdigit() or not last_router.isdigit() or 'vyos' in request.form and not start_delay.isdigit():
            errors.append("At least one field was not filled with a digit!")
        elif int(provider) > 3:
            errors.append("The provider cannot be higher than 3!")
        elif 'mtk' in request.form:
            if int(first_router) not in [10, 11, 12] or int(last_router) not in [10, 11, 12]:
                errors.append("For MikroTik, routers must be 10, 11, or 12!")
        elif int(first_router) > 9 or int(last_router) > 9:
            errors.append("The number of routers cannot be greater than 9!")
        elif int(first_router) > int(last_router):
            errors.append("The number of 'Last Router' cannot be smaller than the number of 'First Router'!")

        if errors:
            for error in errors:
                flash(error, "error")
            return redirect(url_for('creator'))

        args = [provider, first_router, last_router]

        if 'vyos' in request.form:
            args.insert(3, start_delay)
            args.insert(4, release_type)
            script_name = "create_vyos_serial.sh" if request.form.get("SerialMode") else "create_vyos.sh"
            call_script(SCRIPT_DIR, script_name, "vyos", *args)
        elif 'vyos_fast' in request.form:
            args.insert(3, release_type)
            call_script(SCRIPT_DIR, "create_vyos_fast.sh", "vyos_fast", *args)
        elif 'mtk' in request.form:
            args.insert(3, major_version_no)
            args.insert(4, admin_password)
            call_script(SCRIPT_DIR, "create_mtk.sh", "mtk", *args)

        return redirect(url_for('creator'))    
    return render_template('creator.html')

@app.route('/ping-test', methods=['GET', 'POST'])
def ping_test():
    if request.method == 'POST':
        errors = []
        provider = request.form.get("Provider", "").strip()
        first_router = request.form.get("FirstRouter", "").strip()
        last_router = request.form.get("LastRouter", "").strip()

        if not provider or not first_router or not last_router:
            errors.append("At least one field was left empty!")
        elif not provider.isdigit() or not first_router.isdigit() or not last_router.isdigit():
            errors.append("At least one field was not filled with a digit!")
        elif int(provider) > 3:
            errors.append("The provider cannot be greater than 3!")
        elif int(last_router) > 12:
            errors.append("The number of routers cannot be greater than 12!")
        elif (int(provider) == 2 or int(provider) == 3) and int(last_router) > 9:
            errors.append("For Provider 2 and 3 the number of routers cannot be greater than 9!")

        if errors:
            for error in errors:
                flash(error, "error")
            return redirect(url_for('ping_test'))

        # Starts a new thread to execute the script asynchronously
        threading.Thread(target=run_ping_script, args=(provider, first_router, last_router)).start()  
        return redirect(url_for('ping_test'))
    return render_template('ping_test.html')

def run_ping_script(provider, first_router, last_router):
    # Short delay to give the WebSocket client time to connect
    time.sleep(0.3)  # Wait time in seconds
    # Starts the script and forwards the output to SocketIO
    with subprocess.Popen(['./ping.sh', provider, first_router, last_router], stdout=subprocess.PIPE, text=True) as process:
        for line in process.stdout:
            # Send each line of output to the client
            socketio.emit('ping_output', {'data': line})

@app.route('/show-infos', methods=['GET', 'POST'])
def show_infos():
    if request.method == 'POST':
        errors = []
        provider = request.form.get("Provider", "").strip()
        router = request.form.get("Router", "").strip()

        if not provider or not router:
            errors.append("At least one field was left empty!")
        elif not provider.isdigit() or not router.isdigit():
            errors.append("At least one field was not filled with a digit!")
        elif int(provider) > 3:
            errors.append("The provider cannot be greater than 3!")
        elif int(router) > 12:
            errors.append("The router cannot be greater than 12!")
        elif (int(provider) == 2 or int(provider) == 3) and int(router) > 9:
            errors.append("For Provider 2 and 3 the number of routers cannot be greater than 9!")

        if errors:
            for error in errors:
                flash(error, "error")
            return redirect(url_for('show_infos'))
        
        threading.Thread(target=run_show_infos_script, args=(provider, router)).start()
        return redirect(url_for('show_infos'))
    return render_template('show_infos.html')

def run_show_infos_script(provider, router):
    time.sleep(0.3)
    with subprocess.Popen(['./show_infos.sh', provider, router], stdout=subprocess.PIPE, text=True) as process:
        for line in process.stdout:
            socketio.emit('show_infos_output', {'data': line})

@app.route('/backup_restore', methods=['GET', 'POST'])
def backup_restore():
    if request.method == 'POST':
        errors = []
        if 'backup' in request.form:
            provider = request.form.get("Provider", "").strip()
            first_router = request.form.get("FirstRouter", "").strip()
            last_router = request.form.get("LastRouter", "").strip()
            delete_all_backups = "true" if request.form.get("delete_all") else "false"

            if not provider or not first_router or not last_router:
                errors.append("At least one field was left empty!")
            elif not provider.isdigit() or not first_router.isdigit() or not last_router.isdigit():
                errors.append("At least one field was not filled with a digit!")
            elif int(provider) > 3:
                errors.append("The provider cannot be higher than 3!")
            elif int(first_router) > 12 or int(last_router) > 12:
                errors.append("The number of routers cannot be greater than 12!")
            elif int(first_router) > int(last_router):
                errors.append("The number of 'Last Router' cannot be smaller than the number of 'First Router'!")
            elif (int(provider) == 2 or int(provider) == 3) and int(last_router) > 9:
                errors.append("For Provider 2 and 3 the number of routers cannot be greater than 9!")

            if errors:
                for error in errors:
                    flash(error, "error")
                return redirect(url_for('backup_restore'))

            args = [provider, first_router, last_router, delete_all_backups]
            call_script(SCRIPT_DIR, "backup.sh", "backup", *args)

        elif 'backup_id' in request.form:
            vmid = request.form.get("vmid", "").strip()
            delete_all_backups = "true" if request.form.get("delete_all") else "false"

            if not vmid:
                errors.append("Field 'VM ID' was left empty!")
            elif not vmid.isdigit(): 
                errors.append("The 'VM ID' field must be filled with a digit!")

            if errors:
                for error in errors:
                    flash(error, "error")
                return redirect(url_for('backup_restore'))
            
            args = [vmid, delete_all_backups]
            call_script(SCRIPT_DIR, "backup_id.sh", "backup_id", *args)

        elif 'restore' in request.form:
            provider = request.form.get("Provider", "").strip()
            first_router = request.form.get("FirstRouter", "").strip()
            last_router = request.form.get("LastRouter", "").strip()
            start_delay = request.form.get("StartDelay", "").strip()

            if not provider or not first_router or not last_router or not start_delay:
                errors.append("At least one field was left empty!")
            elif not provider.isdigit() or not first_router.isdigit() or not last_router.isdigit() or not start_delay.isdigit():
                errors.append("At least one field was not filled with a digit!")
            elif int(provider) > 3:
                errors.append("The provider cannot be higher than 3!")
            elif int(first_router) > 12 or int(last_router) > 12:
                errors.append("The number of routers cannot be greater than 12!")
            elif int(first_router) > int(last_router):
                errors.append("The number of 'Last Router' cannot be smaller than the number of 'First Router'!")
            elif (int(provider) == 2 or int(provider) == 3) and int(last_router) > 9:
                errors.append("For Provider 2 and 3 the number of routers cannot be greater than 9!")

            if errors:
                for error in errors:
                    flash(error, "error")
                return redirect(url_for('backup_restore'))

            args = [provider, first_router, last_router, start_delay]
            script_name = "restore.sh"
            call_script(SCRIPT_DIR, script_name, "restore", *args)

        elif 'restore_id' in request.form:
            vmid = request.form.get("vmid", "").strip()
            
            if not vmid:
                errors.append("Field 'VM ID' was left empty!")
            elif not vmid.isdigit(): 
                errors.append("The 'VM ID' field must be filled with a digit!")

            if errors:
                for error in errors:
                    flash(error, "error")
                return redirect(url_for('backup_restore'))

            script_name = "restore_id.sh"
            call_script(SCRIPT_DIR, script_name, "restore_id", vmid)

        return redirect(url_for('backup_restore'))
    return render_template('backup_restore.html')

@app.route('/upgrade', methods=['GET', 'POST'])
def upgrade():
    if request.method == 'POST':
        errors = []
        
        provider = request.form.get("Provider", "").strip()
        first_router = request.form.get("FirstRouter", "").strip()
        last_router = request.form.get("LastRouter", "").strip()
        start_delay = request.form.get("StartDelay", "").strip()
        release_type = request.form.get("ReleaseType", "stream").strip()

        if not provider or not first_router or not last_router or not start_delay:
            errors.append("At least one field was left empty!")
        elif not provider.isdigit() or not first_router.isdigit() or not last_router.isdigit() or ('upgrade' in request.form and not start_delay.isdigit()):
            errors.append("At least one field was not filled with a digit!")
        elif int(provider) > 3:
            errors.append("The provider cannot be higher than 3!")
        elif 'mtk_upgrade' in request.form:
            if int(first_router) not in [10, 11, 12] or int(last_router) not in [10, 11, 12]:
                errors.append("For MikroTik upgrade, routers must be 10, 11, or 12!")
        elif int(first_router) > 9 or int(last_router) > 9:
            errors.append("The number of routers cannot be greater than 9!")
        elif int(first_router) > int(last_router):
            errors.append("The number of 'Last Router' cannot be smaller than the number of 'First Router'!")     
        
        if errors:
            for error in errors:
                flash(error, "error")
            return redirect(url_for('upgrade'))
        
        args = [provider, first_router, last_router]

        if 'vyos_upgrade' in request.form:
            args.insert(3, start_delay)
            args.insert(4, release_type)
            script_name = "vyos_upgrade_serial.sh" if request.form.get("SerialMode") else "vyos_upgrade.sh"
            call_script(SCRIPT_DIR, script_name, "vyos_upgrade", *args)
        elif 'vyos_upgrade_fast' in request.form:
            args.insert(3, release_type)
            call_script(SCRIPT_DIR, "vyos_upgrade_fast.sh", "vyos_upgrade_fast", *args)
        elif 'mtk_upgrade' in request.form:
            call_script(SCRIPT_DIR, "mtk_upgrade.sh", "mtk_upgrade", *args)

        return redirect(url_for('upgrade'))
    return render_template('upgrade.html')

@app.route('/controls', methods=['GET', 'POST'])
def controls():
    errors = []
    if request.method == 'POST':
        provider = request.form.get("Provider", "").strip()
        first_router = request.form.get("FirstRouter", "").strip()
        last_router = request.form.get("LastRouter", "").strip()
        start_delay = request.form.get("StartDelay", "").strip()

        if not provider or not first_router or not last_router or (('restart' in request.form or 'start' in request.form) and not start_delay):
            errors.append("At least one field was left empty!")
        elif not provider.isdigit() or not first_router.isdigit() or not last_router.isdigit() or (('restart' in request.form or 'start' in request.form) and not start_delay.isdigit()):
            errors.append("At least one field was not filled with a digit!")
        elif int(provider) > 3:
            errors.append("The provider cannot be higher than 3!")
        elif int(first_router) > 12 or int(last_router) > 12:
            errors.append("The number of routers cannot be greater than 12!")
        elif int(first_router) > int(last_router):
            errors.append("The number of 'Last Router' cannot be smaller than the number of 'First Router'!")
        elif (int(provider) == 2 or int(provider) == 3) and int(last_router) > 9:
            errors.append("For Provider 2 and 3 the number of routers cannot be greater than 9!")

        if errors:
            for error in errors:
                flash(error, "error")
            return redirect(url_for('controls'))

        args = [provider, first_router, last_router]

        action = None
        if 'restart' in request.form:
            action = "restart"
            args.insert(3, start_delay)  # Add Start Delay
        elif 'start' in request.form:
            action = "start"
            args.insert(3, start_delay)
        elif 'shutdown' in request.form:
            action = "shutdown"
        elif 'destroy' in request.form:
            action = "destroy"

        if action:
            script_name = f"{action}.sh"
            call_script(CONTROLS_SCRIPT_DIR, script_name, action, *args)

        return redirect(url_for('controls'))
    return render_template('controls.html')

if __name__ == '__main__':
    app.run(debug=False, host='0.0.0.0', port=21100)
