import sys

# The hook is imported from templates/hooks, which is installed as it
# is: keep __pycache__ out of it.
sys.dont_write_bytecode = True
