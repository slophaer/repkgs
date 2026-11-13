# Test: the build dependencies' python modules are importable in any build, with what they
# propagate (setuptools-scm brings vcs-versioning and packaging)
{
  package,
  buildPkgs,
}:
package {
  name = "test-python-path";
  version = "1";
  source = ./.;
  buildDependencies = [
    buildPkgs.cpython
    buildPkgs.python-setuptools-scm
  ];
  phases = [
    {
      name = "build";
      run = ''
        mkdir $"($c.out)/share"
        ^python3 -c "import setuptools_scm, vcs_versioning, packaging; print('imported')"
          | save $"($c.out)/share/imports"
      '';
    }
  ];
  tests.version = false;
}
