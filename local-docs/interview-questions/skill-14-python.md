Skill 14 — Python (4 questions)
================================

Format: Standard questions only. Project examples are ammunition.
Your remediation pod Python rewrite (bash→Python for K8s API
interaction, Proxmox API calls, Vault token handling, exception
management for multi-API self-healing loop) — inject when earned.

---

1. How do you use Python for automation and scripting in an infrastructure context?

   Coverage check:
   - Python vs bash — when each fits (complexity threshold, API interaction)
   - virtual environments (venv, pip, requirements.txt)
   - argparse for CLI tools
   - f-strings for output formatting
   - logging module vs print (levels, formatters, handlers)
   - os.environ for environment variables
   - sys.exit() and exit codes
   - script structure (main guard, functions, clean separation)

2. How do you interact with external systems from Python?

   Coverage check:
   - requests library (GET, POST, auth headers, status codes, timeout)
   - JSON parsing (json.loads, json.dumps, reading JSON files)
   - YAML parsing (pyyaml)
   - subprocess.run vs Popen (capturing output, return codes, shell=False)
   - os and shutil (path manipulation, file operations)
   - file I/O (open, read, write, context managers — with statement)
   - regular expressions (re module basics)
   - API client libraries (kubernetes, hvac for Vault, proxmoxer)

3. How do you handle errors and exceptions in Python?

   Coverage check:
   - try / except / else / finally
   - catching specific exceptions vs bare except (never bare except)
   - raising exceptions
   - custom exception classes
   - timeout handling for API calls
   - retry patterns (exponential backoff)
   - context managers for cleanup (with statement)
   - logging exceptions with traceback

4. Explain Python data structures — lists, dictionaries, when to use each.

   Coverage check:
   - lists (ordered, indexed, mutable)
   - dictionaries (key-value, fast lookup, unordered before 3.7)
   - sets (unique elements, fast membership test)
   - tuples (immutable, hashable)
   - list comprehensions, dict comprehensions
   - iteration patterns (for loops, enumerate, zip)
   - decorators (basic understanding — what they do, not deep internals)
   - generators (yield, lazy evaluation — awareness level)
