.PHONY: all assemble check clean output_dir

OUTDIR = build

SRC = american_v1.05.s
SRC_MD5 = $(SRC:.s=.md5)

BIN = $(OUTDIR)/$(SRC:.s=.bin)
MD5_CHK = $(BIN:.bin=.md5check)

all: assemble check
assemble: $(BIN)
check: $(MD5_CHK)

output_dir:
	@mkdir -p $(OUTDIR)

$(OUTDIR)/%.md5out: %.md5 output_dir
	@echo "Generating $@"
	@cat $< > $@
	@echo -n "  " >> $@
	@echo -n "${@:.md5out=.bin}" >> $@

$(OUTDIR)/%.md5check: $(OUTDIR)/%.md5out $(OUTDIR)/%.bin 
	md5sum --check $<

$(OUTDIR)/%.bin: %.s output_dir
	waterbear assemble $< -o $@

clean:
	rm -rf $(OUTDIR)


