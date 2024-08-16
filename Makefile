VERSION?=0.0.0
BUILDROOT?=/etc/mock/default.cfg
SELINUXTYPE?=targeted

PREFIX?=/usr/local
DATADIR?=$(PREFIX)/share
INSTALL?=install

.PHONY: build
build: build-py
	sed -i "s|Version:.*|Version:  $(VERSION)|" insights-ansible-playbook-verifier.spec
	@echo "Built $(VERSION)"

.PHONY: build-py
build-py:
	@echo "Building Python package" && \
	cp data/public.gpg python/insights_ansible_playbook_verifier/data/public.gpg
	cp data/revoked_playbooks.yml python/insights_ansible_playbook_verifier/data/revoked_playbooks.yml
	sed -i "s|version = .*|version = '$(VERSION)'|" pyproject.toml


.PHONY: test
test: test-py

.PHONY: test-py
test-py:
	PYTHONPATH=python/ pytest python/tests-unit/ -v


.PHONY: integration
integration: integration-py

.PHONY: integration-py
integration-py:
	PYTHONPATH=python/ pytest python/tests-integration/ -v


.PHONY: check
check: check-py
	gitleaks detect --verbose

.PHONY: check-py
check-py:
	ruff check python/
	ruff format --diff python/
	mypy


.PHONY: tarball
tarball:
	mkdir -p "rpm/"
	rm -rf rpm/insights-ansible-playbook-verifier-$(VERSION).tar.gz
	git ls-files -z | xargs -0 tar \
		--create --gzip \
		--transform "s|^|/insights-ansible-playbook-verifier-$(VERSION)/|" \
		--file rpm/insights-ansible-playbook-verifier-$(VERSION).tar.gz

.PHONY: srpm
srpm:
	rpmbuild -bs \
		--define "_sourcedir `pwd`/rpm" \
		--define "_srcrpmdir `pwd`/rpm" \
		insights-ansible-playbook-verifier.spec

.PHONY: rpm
rpm: build tarball srpm
	mock \
		--root $(BUILDROOT) \
		--rebuild \
		--resultdir "rpm/" \
		rpm/insights-ansible-playbook-verifier-*.src.rpm

.PHONY: selinux-policy
selinux-policy:
	$(MAKE) -C python/selinux -f /usr/share/selinux/devel/Makefile insights_ansible_playbook_verifier.pp
	bzip2 -9 python/selinux/insights_ansible_playbook_verifier.pp

.PHONY: install
install: install-selinux-policy

.PHONY: install-selinux-policy
install-selinux-policy: selinux-policy
	install -D -m 0644 python/selinux/insights_ansible_playbook_verifier.pp.bz2 $(DESTDIR)$(DATADIR)/selinux/packages/$(SELINUXTYPE)/insights_ansible_playbook_verifier.pp.bz2
	install -D -p -m 0644 python/selinux/insights_ansible_playbook_verifier.if $(DESTDIR)$(DATADIR)/selinux/devel/include/distributed/insights_ansible_playbook_verifier.if

.PHONY: clean
clean: clean-rpm

.PHONY: clean-rpm
clean-rpm:
	rm -f rpm/*

.PHONY: clean-selinux-policy
clean-selinux-policy:
	rm -f python/selinux/insights_ansible_playbook_verifier.pp.bz2
	rm -rf python/selinux/tmp/
