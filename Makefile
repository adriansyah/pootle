SRC_DIR = pootle
DOCS_DIR = docs
STATIC_DIR = ${SRC_DIR}/static
ASSETS_DIR = ${SRC_DIR}/assets
CSS_DIR = ${STATIC_DIR}/css
IMAGES_DIR = ${STATIC_DIR}/images
SPRITE_DIR = ${IMAGES_DIR}/sprite
VERSION=$(shell python setup.py --version)
FULLNAME=$(shell python setup.py --fullname)
SFUSERNAME=$(shell egrep -A5 sourceforge ~/.ssh/config | egrep -m1 User | cut -d" " -f2)
FORMATS=--formats=bztar

.PHONY: all build sprite pot mo mo-all requirements help docs assets

all: help

build: docs mo assets
	python setup.py sdist ${FORMATS} ${TAIL}

assets:
	mkdir -p ${ASSETS_DIR}
	python manage.py collectstatic --noinput --clear ${TAIL}
	python manage.py assets build ${TAIL}

docs:
	# Make sure that the submodule with docs theme is pulled and up-to-date.
	git submodule update --init
	# The following creates the HTML docs.
	# NOTE: cd and make must be in the same line.
	cd ${DOCS_DIR}; make html ${TAIL}

sprite:
	glue --sprite-namespace="" --namespace="" ${SPRITE_DIR} --css=${CSS_DIR} --img=${IMAGES_DIR}

pot:
	@${SRC_DIR}/tools/createpootlepot

get-translations:
	ssh pootletranslations ". /var/www/sites/pootle/env/bin/activate; python /var/www/sites/pootle/src/manage.py sync_stores --verbosity=3 --project=pootle"
	rsync -az --delete --exclude="LINGUAS" --exclude=".translation_index" --exclude=pootle-terminology.po pootletranslations:/var/www/sites/pootle/translations/pootle/ ${SRC_DIR}/locale

linguas:
	@${SRC_DIR}/tools/make-LINGUAS.sh 80 > ${SRC_DIR}/locale/LINGUAS

mo:
	python setup.py build_mo ${TAIL}

mo-all:
	python setup.py build_mo --all

publish-pypi:
	python setup.py sdist ${FORMATS} upload

test-publish-pypi:
	 python setup.py sdist ${FORMATS} upload -r https://testpypi.python.org/pypi

#scp -p dist/translate-toolkit-1.10.0.tar.bz2 jsmith@frs.sourceforge.net:/home/frs/project/translate/Translate\ Toolkit/1.10.0/
publish-sourceforge:
	@echo "We don't trust automation that much.  The following is the command you need to run"
	@echo 'scp -p dist/${FULLNAME}.tar.bz2 ${SFUSERNAME}@frs.sourceforge.net:"/home/frs/project/translate/Pootle/${VERSION}/"'
	@echo 'scp -p docs/releases/${VERSION}.rst ${SFUSERNAME}@frs.sourceforge.net:"/home/frs/project/translate/Pootle/${VERSION}/README.rst"'

publish: publish-pypi publish-sourceforge

help:
	@echo "Help"
	@echo "----"
	@echo
	@echo "  build - create sdist with required prep"
	@echo "  sprite - create CSS sprite"
	@echo "  pot - update the POT translations templates"
	@echo "  get-translations - retreive Pootle translations from server (requires ssh config for pootletranslations)"
	@echo "  linguas - update the LINGUAS file with languages over 80% complete"
	@echo "  mo - build MO files for languages listed in 'pootle/locale/LINGUAS'"
	@echo "  mo-all - build MO files for all languages (only use for testing)"
	@echo "  requirements - (re)generate pinned and minimum requirements"
	@echo "  publish-pypi - publish on PyPI"
	@echo "  test-publish-pypi - publish on PyPI testing platform"
	@echo "  publish-sourceforge - publish on sourceforge"
	@echo "  publish - publish on PyPI and sourceforge"

# Perform forced build using -W for the (.PHONY) requirements target
requirements:
	$(MAKE) -W $(REQFILE) min-required.txt requirements.txt

REQS=.reqs
REQFILE=requirements/base.txt

requirements.txt: $(REQFILE)
	@set -e;							\
	 case `pip --version` in					\
	   "pip 0"*|"pip 1.[012]"*)					\
	     virtualenv --no-site-packages --clear $(REQS);		\
	     source $(REQS)/bin/activate;				\
	     echo starting clean install of requirements from PyPI;	\
	     pip install --use-mirrors -r $(REQFILE);			\
	     : trap removes partial/empty target on failure;		\
	     trap 'if [ "$$?" != 0 ]; then rm -f $@; fi' 0;		\
	     pip freeze | grep -v '^wsgiref==' | sort > $@ ;;		\
	   *)								\
	     : only pip 1.3.1+ processes --download recursively;	\
	     rm -rf $(REQS); mkdir $(REQS);				\
	     echo starting download of requirements from PyPI;		\
	     pip install --download $(REQS) -r $(REQFILE);		\
	     : trap removes partial/empty target on failure;		\
	     trap 'if [ "$$?" != 0 ]; then rm -f $@; fi' 0;		\
	     (cd $(REQS) && ls *.tar* |					\
	      sed -e 's/-\([0-9]\)/==\1/' -e 's/\.tar.*$$//') > $@;	\
	 esac; 

min-required.txt: requirements/*.txt
	@if grep -q '>[0-9]' $^; then				\
	   echo "Use '>=' not '>' for requirements"; exit 1;	\
	 fi
	@echo "creating $@"
	@cat $^ | sed -n '/=/{s/>=/==/;s/<.*//;p;}' > $@
