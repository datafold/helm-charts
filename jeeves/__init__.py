# noqa
"""
Jeeves

Before using this package, install the dependencies:

    pip install -r jeeves/requirements.txt

Optional:

    pip install typer-cli
    typer --install-completion

To get help, use:

    j
"""

# Sub-commands
from jeeves.dev import dev
from jeeves.upgrade import upgrade
