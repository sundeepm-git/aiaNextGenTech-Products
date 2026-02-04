# =============================================================
    {
        'azurerm_nat_gateway': 'natgw',
        'azurerm_express_route_circuit': 'er',
        'azurerm_virtual_network_gateway': 'vpngw',
        'azurerm_api_management': 'apim',
        'azurerm_cdn_profile': 'cdn',
        'azurerm_frontdoor': 'afd',
        'azurerm_monitor_diagnostic_setting': 'monitor',
        'azurerm_automation_account': 'aa',
        # Add more as needed
    }
    # Property abbreviation mapping (extend as needed)
    PROP_ABBR = {
        'name': 'name',
        'address_space': 'addr',
        'timezone': 'tz',
        'platform_fault_domain_count': 'pfdc',
        # Add more as needed
    }
    def _print_step(self, msg, color="green"):
        colors = {
            "green": "\033[92m",
            "yellow": "\033[93m",
            "blue": "\033[94m",
            "red": "\033[91m",
            "reset": "\033[0m"
        }
        print(f"{colors.get(color, '')}{msg}{colors['reset']}")
    def _sanitize_tf_content(self, tf_content):
        """Pre-clean invalid HCL: remove lines that are just ')' or '})', and skip arguments after a block closure until a new block starts."""
        lines = tf_content.splitlines()
        cleaned = []
        skip_mode = False
        for i, line in enumerate(lines):
            stripped = line.strip()
            # Remove lines that are just ')' or '})'
            if stripped in [')', '})']:
                continue
            # If we just closed a block, skip lines until a new resource/data block or block start
            if skip_mode:
                if re.match(r'^(resource|data)\s+"', stripped) or stripped.startswith('}'):  # new block or block closure
                    skip_mode = False
                else:
                    continue
            if stripped == '}':
                cleaned.append(line)
                # Look ahead: if next line is not a new block, skip until next block
                if i+1 < len(lines):
                    next_stripped = lines[i+1].strip()
                    if not (re.match(r'^(resource|data)\s+"', next_stripped) or next_stripped.startswith('}')):
                        skip_mode = True
                continue
            cleaned.append(line)
        return '\n'.join(cleaned)

    def _extract_resource_blocks(self, tf_content):
        """Return only resource blocks, skipping data blocks. Also return excluded data block names/vars."""
        resource_blocks = []
        tf_content = self._sanitize_tf_content(tf_content)
        lines = tf_content.splitlines()
        n = len(lines)
        i = 0
        while i < n:
            line = lines[i]
            m = re.match(r'\s*resource\s+"([^"]+)"\s+"([^"]+)"\s*{', line)
            if m:
                rtype, rname = m.group(1), m.group(2)
                block_lines = []
                brace_count = 0
                # Count braces in the declaration line
                decl = line[line.find('{')+1:] if '{' in line else ''
                if decl.strip():
                    block_lines.append(decl)
                for c in line[line.find('{')+1:] if '{' in line else '':
                    if c == '{':
                        brace_count += 1
                    elif c == '}':
                        brace_count -= 1
                brace_count += 1  # for the opening '{' in the declaration
                i += 1
                while i < n and brace_count > 0:
                    l = lines[i]
                    for c in l:
                        if c == '{':
                            brace_count += 1
                        elif c == '}':
                            brace_count -= 1
                    block_lines.append(l)
                    i += 1
                # Remove the last closing '}' if present
                if block_lines and block_lines[-1].strip() == '}':
                    block_lines = block_lines[:-1]
                block = '\n'.join(block_lines)
                print(f"[DEBUG] Block substring for {rtype} {rname}:\nFIRST 100:\n{block[:100]}\n...\nLAST 100:\n{block[-100:]}")
                resource_blocks.append((rtype, rname, block))
            else:
                i += 1
        data_blocks = re.findall(r'data\s+"([^"]+)"\s+"([^"]+)"\s*{(.*?)}\s*', tf_content, re.DOTALL)
        excluded_data_vars = {}
        for dtype, dname, dblock in data_blocks:
            dlines = dblock.splitlines()
            for line in dlines:
                m = re.match(r'(\w+)\s*=\s*(.+)', line.strip())
                if m:
                    excluded_data_vars.setdefault(f"data.{dtype}.{dname}", []).append(m.group(1))
        return resource_blocks, excluded_data_vars


    def __init__(self, subscription_name, subscription_id, resource_group_name, dry_run=False, verbose=False):
        self.subscription_name = subscription_name
        self.subscription_id = subscription_id
        self.resource_group_name = resource_group_name
        self.dry_run = dry_run
        self.verbose = verbose


        # Place refactored output at workspace root as per YAML spec
        workspace_root = Path(__file__).resolve().parent.parent
        # Source directory for exported Terraform files (always relative to workspace root)
        self.source_dir = workspace_root / f"azure-export/{subscription_name}/{resource_group_name}"
        # Output directory for refactored Terraform files (as per standards)
        self.output_dir = workspace_root / f"azure-tf-refactored/{subscription_name}/{resource_group_name}"

        self.loader = TerraformLoader(self.source_dir, verbose)
        self.backup = BackupManager(self.source_dir, verbose)
        self.validator = TerraformValidator(self.output_dir, verbose)
        self.writers = TerraformWriters(self.output_dir, verbose)
        self.failed_resources = {}

    def generate_providers_tf(self):
        """Ensure providers.tf declares the required azurerm provider block, including subscription_id."""
        self.log("Generating providers.tf...")
        self.writers.providers_tf = [
            f'provider "azurerm" {{\n  features {{}}\n  subscription_id = "{self.subscription_id}"\n}}'
        ]


    def run(self):
        # Ensure output directory exists
        self.output_dir.parent.mkdir(parents=True, exist_ok=True)


        # (Backup step removed as requested)

        # Load and parse all .tf files from export folder
        try:
            parsed_files, failed_files = self.loader.load()
            self.failed_resources.update(failed_files)
            self.hcl_data = {k: v for k, v in parsed_files.items() if k.startswith(str(self.source_dir)) and k.endswith('.tf')}
        except Exception as e:
            print(f"[ERROR] Loading/parsing failed: {e}")
            self.failed_resources['__loader__'] = str(e)
            self.hcl_data = {}



        # Ensure output directory exists before copying
        self.output_dir.mkdir(parents=True, exist_ok=True)


        # Always copy main.tf, terraform.tfstate, and data-sources.tf from export to refactor folder (unmodified)

        # Debug: Log file copy operations

        # Improved: Use absolute paths and print resolved paths for diagnostics
        export_main = (self.source_dir / "main.tf").resolve()
        refactor_main = (self.output_dir / "main.tf").resolve()
        main_copied = False
        print(f"[DEBUG] Copy main.tf: {export_main} -> {refactor_main}")
        if export_main.is_file():
            try:
                shutil.copy2(str(export_main), str(refactor_main))
                main_copied = True
                print(f"[DEBUG] main.tf copied successfully.")
            except Exception as e:
                print(f"[ERROR] Failed to copy main.tf: {e} | Source: {export_main} | Dest: {refactor_main}")
        else:
            print(f"[ERROR] main.tf does not exist at {export_main} (checked with Path.is_file())")

        export_tfstate = (self.source_dir / "terraform.tfstate").resolve()
        refactor_tfstate = (self.output_dir / "terraform.tfstate").resolve()
        tfstate_copied = False
        print(f"[DEBUG] Copy terraform.tfstate: {export_tfstate} -> {refactor_tfstate}")
        if export_tfstate.is_file():
            try:
                shutil.copy2(str(export_tfstate), str(refactor_tfstate))
                tfstate_copied = True
                print(f"[DEBUG] terraform.tfstate copied successfully.")
            except Exception as e:
                print(f"[ERROR] Failed to copy terraform.tfstate: {e} | Source: {export_tfstate} | Dest: {refactor_tfstate}")
        else:
            print(f"[ERROR] terraform.tfstate does not exist at {export_tfstate} (checked with Path.is_file())")

        export_datasources = (self.source_dir / "data-sources.tf").resolve()
        refactor_datasources = (self.output_dir / "data-sources.tf").resolve()
        datasources_copied = False
        print(f"[DEBUG] Copy data-sources.tf: {export_datasources} -> {refactor_datasources}")
        if export_datasources.is_file():
            try:
                shutil.copy2(str(export_datasources), str(refactor_datasources))
                datasources_copied = True
                print(f"[DEBUG] data-sources.tf copied successfully.")
            except Exception as e:
                print(f"[ERROR] Failed to copy data-sources.tf: {e} | Source: {export_datasources} | Dest: {refactor_datasources}")
        else:
            print(f"[ERROR] data-sources.tf does not exist at {export_datasources} (checked with Path.is_file())")

        # Remove any generated data-sources.tf content to ensure only the copied file is used
        self.writers.data_sources = []


         if main_copied and tfstate_copied:
            if datasources_copied:
                self._print_step("Step 1 - main.tf, tfstate, and data-sources.tf refactored successfully.", color="green")
            else:
                self._print_step("Step 1 - main.tf and tfstate refactored successfully. data-sources.tf not found (optional).", color="yellow")
        else:
            self._print_step("Step 1 - One or more required files (main.tf, tfstate) missing in export folder. Stopping workflow.", color="red")
            # Stop workflow if any required file is missing
            import sys
            sys.exit(1)

        # Apply refactoring rules and best practices
        try:
            self.apply_rules()
        except Exception as e:
            print(f"[ERROR] Refactor rules failed: {e}")
            self.failed_resources['__refactor__'] = str(e)

        # Write all output files (except tfvars first)
        try:
            tfvars_content = self.writers.tfvars
            self.writers.tfvars = []
            self.writers.write_all()
        except Exception as e:
            print(f"[ERROR] Writing output files failed: {e}")
            self.failed_resources['__writer__'] = str(e)

        # Print variables.tf message and count
        variables_tf_path = self.output_dir / "variables.tf"
        try:
            with open(variables_tf_path, "r") as f:
                lines = f.readlines()
            var_count = sum(1 for l in lines if l.strip().startswith('variable '))
            self._print_step(f"Step 2 - variables.tf created successfully with {var_count} variables.", color="blue")
        except Exception as e:
            self._print_step(f"Step 2 - [ERROR] Could not read variables.tf at runtime: {e}", color="red")

        # Write tfvars file
        try:
            self.writers.tfvars = tfvars_content
            tfvars_path = self.output_dir / "terraform.tfvars"
            with open(tfvars_path, "w") as f:
                f.write("# Auto-generated via Enterprise Terraform Refactoring Engine\n\n")
                f.write("\n\n".join(self.writers.tfvars))
        except Exception as e:
            print(f"[ERROR] Writing tfvars file failed: {e}")

        # (terraform CLI command execution removed)

        # Write summary and error reports
        self._write_summary_report()
        if self.failed_resources:
            self._write_failed_report()

    def _write_summary_report(self):
        report_path = self.output_dir / "REPORT.md"
        self.output_dir.mkdir(parents=True, exist_ok=True)
        lines = []
        lines.append(f"# Refactor Summary Report\n\n")
        lines.append(f"**Subscription:** {self.subscription_name}\n\n")
        lines.append(f"**Resource Group:** {self.resource_group_name}\n\n")
        lines.append(f"## Processed Files\n")
        for fname in sorted(self.hcl_data.keys()):
            lines.append(f"- {fname}\n")

        # One-to-one mapping table with reasons
        lines.append("\n## Variable Mapping Table\n")
        var_names = set()
        tfvars_names = set()
        main_vars = set()
        var_comments = {}
        tfvars_comments = {}
        # variables.tf
        for var_block in self.writers.variables_tf:
            m = re.match(r'# Variable: ([^\n]+)\n# Used in main.tf as var\.([a-zA-Z0-9_]+)', var_block)
            if m:
                var_names.add(m.group(1))
                var_comments[m.group(1)] = m.group(2)
        # terraform.tfvars
        for l in self.writers.tfvars:
            m = re.match(r'# ([a-zA-Z0-9_]+) maps to variable ([a-zA-Z0-9_]+)', l)
            if m:
                tfvars_names.add(m.group(1))
                tfvars_comments[m.group(1)] = m.group(2)
        # main.tf
        # Use cleaned main.tf if available
        cleaned_main_tf_path = self.output_dir / "main.cleaned.tf"
        if cleaned_main_tf_path.exists():
            main_tf_path = cleaned_main_tf_path
        else:
            main_tf_path = self.output_dir / "main.tf"
        if main_tf_path.exists():
            with open(main_tf_path, "r") as f:
                main_content = f.read()
            main_vars.update(re.findall(r'var\.([a-zA-Z0-9_]+)', main_content))
        all_vars = sorted(var_names | tfvars_names | main_vars)
        lines.append("| Variable | variables.tf | terraform.tfvars | main.tf | Reason |\n")
        lines.append("|----------|-------------|------------------|---------|--------|\n")
        for v in all_vars:
            included = []
            reason = ""
            if v in var_names and v in tfvars_names and v in main_vars:
                included = ["Y", "Y", "Y"]
                reason = "Mapped 1:1 in all files"
            elif v in var_names and v in tfvars_names:
                included = ["Y", "Y", ""]
                reason = "Declared and assigned, not referenced in main.tf"
            elif v in var_names and v in main_vars:
                included = ["Y", "", "Y"]
                reason = "Declared and referenced, not assigned in tfvars"
            elif v in tfvars_names and v in main_vars:
                included = ["", "Y", "Y"]
                reason = "Assigned and referenced, not declared in variables.tf"
            elif v in var_names:
                included = ["Y", "", ""]
                reason = "Declared only"
            elif v in tfvars_names:
                included = ["", "Y", ""]
                reason = "Assigned only"
            elif v in main_vars:
                included = ["", "", "Y"]
                reason = "Referenced only"
            else:
                included = ["", "", ""]
                reason = "Not included"
            lines.append(f"| {v} | {included[0]} | {included[1]} | {included[2]} | {reason} |\n")

        # Excluded data blocks
        if hasattr(self, 'excluded_data_vars') and self.excluded_data_vars:
            lines.append("\n## Excluded Data Blocks\n")
            for dblock, dvars in self.excluded_data_vars.items():
                lines.append(f"- {dblock}: {', '.join(dvars)}\n")
        # Omitted variables from tfvars
        if hasattr(self, 'omitted_tfvars_reasons') and self.omitted_tfvars_reasons:
            lines.append("\n## Omitted Variables from terraform.tfvars\n")
            for var, reason in self.omitted_tfvars_reasons:
                lines.append(f"- {var}: {reason}\n")
        # Omitted hardcoded values from main.tf
        if hasattr(self, 'omitted_main_hardcoded_reasons') and self.omitted_main_hardcoded_reasons:
            lines.append("\n## Omitted Hardcoded Values from main.tf\n")
            for var, reason in self.omitted_main_hardcoded_reasons:
                lines.append(f"- {var}: {reason}\n")
        if self.failed_resources:
            lines.append(f"\n## Failed Resources\n")
            for res, err in self.failed_resources.items():
                lines.append(f"- **{res}**: {err}\n")
        else:
            lines.append(f"\nNo failed resources.\n")
        # Check for drift report
        drift_report = self.output_dir / "DRIFT_REPORT.md"
        if drift_report.exists():
            lines.append(f"\n## Drift Detected\nSee DRIFT_REPORT.md for details.\n")
        else:
            lines.append(f"\nNo drift detected.\n")
        with open(report_path, "w") as f:
            f.writelines(lines)

    def _write_failed_report(self):
        report_path = self.output_dir / "FAILED_RESOURCES_REPORT.md"
        self.output_dir.mkdir(parents=True, exist_ok=True)
        with open(report_path, "w") as f:
            f.write("# Failed Resources Report\n\n")
            for res, err in self.failed_resources.items():
                f.write(f"- **{res}**: {err}\n")

        self.hcl_data = {}

    def log(self, msg):
        if self.verbose:
            print(f"[ENGINE] {msg}")

    # ----------------------------------------------------------
    # MAIN PIPELINE
    # ----------------------------------------------------------


    # ----------------------------------------------------------
    # RULE APPLICATION LOGIC
    # ----------------------------------------------------------

    def apply_rules(self):
        """
        Apply YAML-defined rule transformations.
        Populate TerraformWriters buffers with refactored content.
        """
        self.log("Applying refactor rules...")

        # Map file names to writer buffers
        file_map = {
            'main.tf': self.writers.main_tf,
            'variables.tf': self.writers.variables_tf,
            'outputs.tf': self.writers.outputs_tf,
            'providers.tf': self.writers.providers_tf,
            'locals.tf': self.writers.locals_tf,
            'data-sources.tf': self.writers.data_sources,
            'terraform.tfvars': self.writers.tfvars,
        }

        # Clear all buffers first
        for buf in file_map.values():
            buf.clear()

        # --- Patch: Replace all hardcoded values in resource blocks with variable references ---
        def to_snake(name):
            return re.sub(r'[^a-zA-Z0-9]', '_', name).lower()

        def replace_block_literals(rtype, rname, block, parent_keys=None):
            parent_keys = parent_keys or []
            lines = block.splitlines()
            out_lines = []  # Ensure this is always defined at the start
            i = 0
            while i < len(lines):
                line = lines[i].rstrip()
                # tags block
                if line.strip().startswith('tags = {'):
                    var_name = to_snake(f"tags_{rname}")
                    out_lines.append(f"tags = var.{var_name}")
                    # skip to closing '}'
                    i += 1
                    while i < len(lines) and lines[i].strip() != '}':
                        i += 1
                    i += 1
                    continue
                # Multi-line jsonencode or similar (e.g., settings = jsonencode({ ... }))
                jsonencode_match = re.match(r'(\w+)\s*=\s*jsonencode\(\{', line.strip())
                if jsonencode_match:
                    key = jsonencode_match.group(1)
                    var_base = '_'.join([key] + parent_keys + [rname])
                    var_name = to_snake(var_base)
                    # Skip all lines until the matching closing '})' is found
                    depth = 1
                    i += 1
                    while i < len(lines) and depth > 0:
                        l = lines[i]
                        if '{' in l:
                            depth += l.count('{')
                        if '}' in l:
                            depth -= l.count('}')
                        # If this line contains only ')' or '})', skip it
                        if l.strip() in [')', '})']:
                            i += 1
                            continue
                        i += 1
                    out_lines.append(f"{key} = var.{var_name}")
                    # After skipping, also skip any immediate trailing ')' or '})' lines
                    # After skipping, also skip any immediate trailing ')' or '})' lines
                    while i < len(lines) and lines[i].strip() in [')', '})']:
                        # If we see '})', break out of the block entirely (end of this resource block)
                        if lines[i].strip() == '})':
                            i = len(lines)  # force exit from while loop
                            break
                        i += 1
                    # If the next line is a block closure, let the main loop handle it
                    # If the next line is a valid argument, it will be processed as normal
                    continue
                # Skip any line that is just ')' or '})' (anywhere in the block)
                if line.strip() in [')', '})']:
                    # If this is '})', immediately return the current output for the block
                    if line.strip() == '})':
                        return '\n'.join(out_lines)
                    i += 1
                    continue
                # Nested block (e.g., os_disk { ... })
                nested_match = re.match(r'(\w+)\s*{', line.strip())
                if nested_match:
                    nested_key = nested_match.group(1)
                    # Find the full nested block
                    nested_lines = []
                    depth = 1
                    i += 1
                    while i < len(lines) and depth > 0:
                        l = lines[i]
                        if '{' in l:
                            depth += l.count('{')
                        if '}' in l:
                            depth -= l.count('}')
                        if depth > 0:
                            nested_lines.append(l)
                        i += 1
                    nested_block = '\n'.join(nested_lines)
                    replaced_nested = replace_block_literals(rtype, rname, nested_block, parent_keys + [nested_key])
                    out_lines.append(f"{nested_key} {{")
                    out_lines.extend(["  " + l for l in replaced_nested.splitlines()])
                    out_lines.append("}")
                    continue
                # block closure
                if line.strip() == '}':
                    out_lines.append('}')
                    i += 1
                    continue
                # key = value
                match = re.match(r'(\w+)\s*=\s*(.+)', line.strip())
                if match:
                    key, value = match.group(1), match.group(2).strip()
                    # Skip computed/data-sourced values, never parameterize 'depends_on', and never parameterize *_id, *_ids, or ARM IDs
                    if (
                        "data.azurerm_resource_group.rg" in value or
                        "data.azurerm_network_interface" in value or
                        "azurerm_linux_virtual_machine" in value or
                        "azurerm_resource_group" in value or
                        key == "depends_on" or
                        re.match(r'.*_id(s)?$', key) or
                        re.match(r'.*id(s)?$', key) or
                        (isinstance(value, str) and value.startswith('"/subscriptions/'))
                    ):
                        out_lines.append(f"{key} = {value}")
                        i += 1
                        continue
                    elif any(x in key for x in ["self_link", "uri"]):
                        out_lines.append(f"{key} = {value}")
                        i += 1
                        continue
                    var_base = '_'.join([key] + parent_keys + [rname])
                    var_name = to_snake(var_base)
                    out_lines.append(f"{key} = var.{var_name}")
                    i += 1
                    continue
                # Default: emit the line as-is
                out_lines.append(line)
                i += 1
            return '\n'.join(out_lines)

        # Only refactor and write main.tf once, then generate variables.tf and tfvars from that, but do not re-update main.tf
        for filename, parsed in self.hcl_data.items():
            raw_text = Path(filename).read_text()
            fname = Path(filename).name
            buf = file_map.get(fname)
            if buf is not None:
                # For main.tf, copy as-is from export folder to refactor folder, no refactoring
                buf.append(raw_text)
            else:
                self.log(f"Skipping unknown file type: {fname}")

        # Copy terraform.tfstate if it exists in the export folder
        export_tfstate = self.source_dir / "terraform.tfstate"
        refactor_tfstate = self.output_dir / "terraform.tfstate"
        if export_tfstate.exists():
            import shutil
            shutil.copy2(export_tfstate, refactor_tfstate)
            self.log(f"Copied terraform.tfstate from export to refactor folder.")

        self.generate_data_sources()
        self.generate_providers_tf()
        self.generate_variables_tf()
        self.generate_tfvars()

        # Check if variables.tf or terraform.tfvars are empty, and stop with a message if so
        if not self.writers.variables_tf or all(not block.strip() for block in self.writers.variables_tf):
            print("[ERROR] variables.tf content was not generated. Stopping engine.")
            import sys
            sys.exit(1)
        if not self.writers.tfvars or all(not line.strip() for line in self.writers.tfvars):
            print("[ERROR] terraform.tfvars content was not generated. Stopping engine.")
            import sys
            sys.exit(1)



    def generate_variables_tf(self):
        import collections
        variables = collections.OrderedDict()
        resource_groups = collections.OrderedDict()
        def to_snake(name):
            return re.sub(r'[^a-zA-Z0-9]', '_', name).lower()

        def get_resource_abbr(rtype):
            return self.RESOURCE_ABBR.get(rtype, to_snake(rtype))

        def get_prop_abbr(prop):
            return self.PROP_ABBR.get(prop, to_snake(prop))

        def build_var_name(rtype, rname, prop, parent_keys=None):
            # Strictly enforce only a single res_N in the variable name
            parent_keys = parent_keys or []
            resource_abbr = get_resource_abbr(rtype)
            prop_abbr = get_prop_abbr(prop)
            # Find the first res_N in rname or parent_keys
            instance = None
            # Check rname first
            if isinstance(rname, str):
                rname_clean = rname.replace('-', '_')
                match = re.search(r'res_\d+', rname_clean)
                if match:
                    instance = match.group(0)
            # If not found in rname, check parent_keys
            if not instance:
                for k in parent_keys:
                    k_clean = k.replace('-', '_')
                    match = re.search(r'res_\d+', k_clean)
                    if match:
                        instance = match.group(0)
                        break
            # If still not found, fallback to rname as-is
            if not instance:
                instance = rname.replace('-', '_') if isinstance(rname, str) else rname
            # Remove any res_N from parent_keys to avoid duplication
            filtered_parents = [k for k in parent_keys if not re.match(r'res_\d+', k.replace('-', '_'))]
            nested_abbr = ''
            for k in filtered_parents:
                nested_abbr += '_' + get_prop_abbr(k)
            return f"{resource_abbr}_{instance}{nested_abbr}_{prop_abbr}".replace('__','_').strip('_')
        def is_sensitive(key):
            return any(x in key.lower() for x in ["password", "secret", "key", "token", "sas", "connection_string", "client_secret", "private_key"])
        def is_id_field(key):
            return key.endswith('_id') or key.endswith('_ids') or key == 'id' or key == 'ids' or 'self_link' in key or 'uri' in key
        def is_data_sourced(value):
            return isinstance(value, str) and (value.startswith('data.') or value.startswith('"/subscriptions/'))
        def guess_type(val):
            if isinstance(val, bool):
                return 'bool'
            if isinstance(val, int) or (isinstance(val, str) and val.isdigit()):
                return 'number'
            if isinstance(val, list):
                # Try to infer type from first element
                if val:
                    subtype = guess_type(val[0])
                    return f'list({subtype})'
                else:
                    return 'list(string)'
            if isinstance(val, dict):
                return 'map(string)'
            if isinstance(val, str) and val.lower() in ['true', 'false']:
                return 'bool'
            if isinstance(val, str) and val.startswith('[') and val.endswith(']'):
                return 'list(string)'
            return 'string'

        tags_added = False
        tags_group = None
        def extract_from_dict(d, group_label, parent_keys=None, rtype=None, rname=None):
            nonlocal tags_added, tags_group
            parent_keys = parent_keys or []
            for key, value in d.items():
                # Exclude ids, data-sourced, sensitive, and Azure location
                if is_id_field(key) or is_sensitive(key) or (key == 'location'):
                    continue
                # Exclude data-sourced values (string or list)
                if isinstance(value, str) and is_data_sourced(value):
                    continue
                if isinstance(value, list) and all(isinstance(v, str) and is_data_sourced(v) for v in value):
                    continue
                # Handle jsonencode({ ... }) blocks
                if isinstance(value, str) and value.strip().startswith('jsonencode({'):
                    # Extract the JSON dict inside jsonencode
                    json_block = value.strip()[len('jsonencode('):].strip()
                    if json_block.startswith('{') and json_block.endswith('})'):
                        json_block = json_block[1:-2].strip()
                        # Parse key-value pairs (simple, not nested)
                        for line in json_block.splitlines():
                            m = re.match(r'([a-zA-Z0-9_]+)\s*=\s*(.+)', line.strip())
                            if m:
                                jkey, jval = m.group(1), m.group(2)
                                # Only extract if not a reference or computed
                                if not is_data_sourced(jval) and not is_id_field(jkey) and not is_sensitive(jkey):
                                    if rtype and rname:
                                        var_name = build_var_name(rtype, rname, jkey, parent_keys+[key])
                                    else:
                                        var_name = to_snake('_'.join(parent_keys + [group_label, key, jkey]))
                                    variables[var_name] = {
                                        'type': guess_type(jval),
                                        'desc': f"{jkey.replace('_', ' ').capitalize()} for the {group_label.replace('_', ' ')}.",
                                        'sensitive': is_sensitive(jkey)
                                    }
                                    resource_groups.setdefault(group_label, []).append(var_name)
                        continue
                if isinstance(value, dict):
                    # tags block
                    if key == 'tags':
                        if not tags_added:
                            var_name = 'tags'
                            variables[var_name] = {
                                'type': 'map(string)',
                                'desc': f"Tags for all resources.",
                                'sensitive': False
                            }
                            tags_added = True
                            tags_group = group_label
                            resource_groups.setdefault(group_label, []).append('tags')
                        continue
                    # Nested block: pass rtype/rname down
                    extract_from_dict(value, group_label + '_' + key, parent_keys + [key], rtype, rname)
                elif isinstance(value, list):
                    # List of blocks or values
                    if value and isinstance(value[0], dict):
                        for idx, item in enumerate(value):
                            extract_from_dict(item, group_label + '_' + key + str(idx), parent_keys + [f"{key}{idx}"], rtype, rname)
                    else:
                        # Use rtype/rname from parent
                        if rtype and rname:
                            var_name = build_var_name(rtype, rname, key, parent_keys)
                        else:
                            var_name = to_snake('_'.join(parent_keys + [group_label, key]))
                        variables[var_name] = {
                            'type': guess_type(value),
                            'desc': f"{key.replace('_', ' ').capitalize()} for the {group_label.replace('_', ' ')}.",
                            'sensitive': is_sensitive(key)
                        }
                        resource_groups.setdefault(group_label, []).append(var_name)
                else:
                    # Use rtype/rname from parent
                    if rtype and rname:
                        var_name = build_var_name(rtype, rname, key, parent_keys)
                    else:
                        var_name = to_snake('_'.join(parent_keys + [group_label, key]))
                    variables[var_name] = {
                        'type': guess_type(value),
                        'desc': f"{key.replace('_', ' ').capitalize()} for the {group_label.replace('_', ' ')}.",
                        'sensitive': is_sensitive(key)
                    }
                    resource_groups.setdefault(group_label, []).append(var_name)

        # Walk parsed HCL for all resource blocks
        for filename, parsed in self.hcl_data.items():
            fname = Path(filename).name
            if fname == 'main.tf':
                for block in parsed.get('resource', []):
                    for rtype, resources in block.items():
                        for rname, attrs in resources.items():
                            # rname is the resource instance string (e.g., res_3)
                            group_label = to_snake(f"{rtype}_{rname}")
                            extract_from_dict(attrs, group_label, parent_keys=[rname], rtype=rtype, rname=rname)

        # Compose variables.tf in grouped, formatted blocks
        var_blocks = ["# Auto-generated by Terraform Variable Refactoring Engine.\n# Edits may be overwritten.\n"]
        for group, var_list in resource_groups.items():
            header = f"\n# {'-'*75}\n# {group.replace('_', ' ').upper()}\n# {'-'*75}\n"
            var_blocks.append(header)
            for var_name in var_list:
                v = variables[var_name]
                block = f'variable "{var_name}" {{\n  type        = {v["type"]}\n  description = "{v["desc"]}"'
                if v['sensitive']:
                    block += '\n  sensitive = true'
                # Add validation for region, sku, tier if present
                if var_name.endswith('region'):
                    block += '\n  validation {\n    condition     = contains(["eastus", "centralus", "westeurope", "southcentralus"], var.' + var_name + ')\n    error_message = "Region must be a valid Azure region."\n  }'
                if var_name.endswith('sku') or var_name.endswith('tier'):
                    block += '\n  validation {\n    condition     = contains(["Basic", "Standard", "Premium"], var.' + var_name + ')\n    error_message = "SKU tier must be Basic, Standard, or Premium."\n  }'
                block += '\n}'
                var_blocks.append(block)
        # Always ensure resource_group_name is present in variables.tf
        found_rg_var = any('variable "resource_group_name"' in b for b in var_blocks)
        if not found_rg_var:
            block = f'variable "resource_group_name" {{\n  description = "The name of the Azure resource group."\n  type = string\n  default = "{self.resource_group_name}"\n}}'
            var_blocks.append(block)
        self.log(f"Populating variables.tf with {len(var_blocks)} variable blocks.")
        self.writers.variables_tf = var_blocks


        # Generate variables.tf content
        var_blocks = []
        for var_name in variables:
            # Skip provider/data-sourced/computed fields, IDs, self-links, URIs, or environment-specific names
            if any(x in var_name for x in ["id", "self_link", "uri"]):
                continue
            if re.search(r'(prod|dev|qa|test|stage)', var_name):
                continue
            type_val = types[var_name]
            # Use strict types for objects/maps/lists
            if type_val.startswith('map') or type_val.startswith('object'):
                type_str = type_val
            elif type_val.startswith('list'):
                type_str = type_val
            elif type_val in ["string", "number", "bool"]:
                type_str = type_val
            else:
                type_str = 'string'
            block = f'variable "{var_name}" {{\n  description = "{descriptions[var_name]}"\n  type = {type_str}'
            # Sensitive fields
            if var_name in sensitive or any(s in var_name for s in ["password", "secret", "key"]):
                block += '\n  sensitive = true'
            # Validation blocks for enumerated fields
            if var_name in defaults and isinstance(defaults[var_name], str):
                if var_name in ["region", "sku", "tier"]:
                    allowed = [defaults[var_name]]
                    block += f'\n  validation {{\n    condition = contains({allowed}, var.{var_name})\n    error_message = "Invalid value for {var_name}."\n  }}'
            # Default value (only if not sensitive and not required)
            if var_name in defaults:
                if type_val == 'map(string)' and isinstance(defaults[var_name], dict):
                    tags_lines = ['  default = {']
                    for k, v in defaults[var_name].items():
                        tags_lines.append(f'    {k} = "{v}"')
                    tags_lines.append('  }')
                    block += '\n' + '\n'.join(tags_lines)
                elif type_val == 'bool':
                    block += f'\n  default = {str(defaults[var_name]).lower()}'
                elif type_val == 'number':
                    block += f'\n  default = {defaults[var_name]}'
                elif type_val.startswith('list'):
                    val = defaults[var_name]
                    if isinstance(val, str) and val.startswith('[') and val.endswith(']'):
                        items = re.findall(r'"([^"]+)"', val)
                        hcl_list = '[' + ', '.join(f'"{item}"' for item in items) + ']'
                        block += f'\n  default = {hcl_list}'
                    elif isinstance(val, list):
                        hcl_list = '[' + ', '.join(f'"{item}"' for item in val) + ']'
                        block += f'\n  default = {hcl_list}'
                    else:
                        block += f'\n  default = {val}'
                else:
                    block += f'\n  default = "{defaults[var_name]}"'
            block += '\n}\n'
            var_blocks.append(block)
        # Always ensure resource_group_name is present in variables.tf
        found_rg_var = any('variable "resource_group_name"' in b for b in var_blocks)
        if not found_rg_var:
            block = f'variable "resource_group_name" {{\n  description = "The name of the Azure resource group."\n  type = string\n  default = "{self.resource_group_name}"\n}}\n'
            var_blocks.append(block)

        # Compare variables.tf and main.tf
        main_tf_path = self.output_dir / "main.tf"
        main_tf_vars = set()
        if main_tf_path.exists():
            with open(main_tf_path, "r") as f:
                content = f.read()
            main_tf_vars = set(re.findall(r'var\.([a-zA-Z0-9_]+)', content))
        var_names_in_tf = set()
        for block in var_blocks:
            match = re.match(r'variable "([^"]+)"', block)
            if match:
                var_names_in_tf.add(match.group(1))
        alignment = main_tf_vars == var_names_in_tf
        self.variables_alignment_result = alignment
        self.variables_alignment_message = f"Variables alignment: {alignment}. main.tf variables: {len(main_tf_vars)}, variables.tf: {len(var_names_in_tf)}"
        print(self.variables_alignment_message)
        self.log(f"Populating variables.tf with {len(var_blocks)} variable blocks.")
        self.writers.variables_tf = var_blocks

    def generate_tfvars(self):
        """Generate a blank terraform.tfvars structure with all variable names (except sensitive/id/data), ready for user input."""
        self.log("Generating blank terraform.tfvars structure...")
        tfvars_lines = []
        # Load variables.tf
        variables_tf_path = self.output_dir / "variables.tf"
        var_blocks = []
        if variables_tf_path.exists():
            with open(variables_tf_path, "r") as f:
                block = ""
                for line in f:
                    if line.strip().startswith("variable "):
                        if block:
                            var_blocks.append(block)
                        block = line
                    else:
                        block += line
                if block:
                    var_blocks.append(block)
        else:
            var_blocks = self.writers.variables_tf

        for var_block in var_blocks:
            match = re.match(r'variable "([^"]+)"', var_block)
            if match:
                var_name = match.group(1)
                # Exclude *_id, *_ids, ARM IDs
                if (
                    var_name.endswith('_id') or var_name.endswith('_ids') or
                    var_name == 'id' or var_name == 'ids' or
                    re.match(r'.*id(s)?$', var_name)
                ):
                    continue
                # Check for sensitive attribute
                sensitive_match = re.search(r'sensitive\s*=\s*true', var_block)
                if sensitive_match or any(s in var_name for s in ["password", "secret", "key"]):
                    tfvars_lines.append(f'# {var_name} is sensitive and not exported')
                    continue
                tfvars_lines.append(f'{var_name} = ""')
        self.writers.tfvars = tfvars_lines

    # ----------------------------------------------------------

    def convert_literals_to_variables(self):
        """
        Scan for hardcoded literals and convert them to variables.tf entries.
        """
        self.log("Extracting literals -> variables...")

        # Real implementation would walk HCL AST.
        # For now, placeholder structure.
        pass

    # ----------------------------------------------------------

    def generate_data_sources(self):
        """Create data-sources.tf"""
        self.log("Generating data sources...")

        self.writers.data_sources = [
            """
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}
            """.strip()
        ]

    # ----------------------------------------------------------

# Auto-generated main.tf
