# Default tests follow the active FO submission. Legacy: make -f Makefile.legacy
PYTHON ?= python3
GATES ?= no
FO_TEST_DIR := ../src/improvement_plan/fo_transform/test
.PHONY: all clean

ifeq ($(GATES),yes)
all:
	$(PYTHON) $(FO_TEST_DIR)/run_gate_tests.py
clean:
	$(PYTHON) $(FO_TEST_DIR)/run_gate_tests.py --clean
else
all:
	$(PYTHON) run_active_tests.py --simulator icarus
clean:
	$(PYTHON) run_active_tests.py --clean
endif
