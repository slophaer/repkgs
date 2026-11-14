{
  package,
  buildPkgs,
  platform,
  on,
}:
package {
  name = "openssl";
  # engines, providers and the default openssl.cnf (etc/ssl) next to the loaded libcrypto (reloc.h)
  # instead of a configured libdir and OPENSSLDIR: no build reads the build machine's
  # /etc/ssl/openssl.cnf. OPENSSL_CONF still wins
  patches = [ ./relocatable.patch ];
  cc.cflags = [ "-DOSSL_RELOCATABLE" ];
  uses = [ "make" ];
  # --openssldir is the ambient path, not a store path: the machine's certificates (cert.pem, certs/)
  make.configureScript = "Configure";
  make.configureFlags = [
    platform.opensslTarget
    "--libdir=lib"
    "--openssldir=/etc/ssl"
    "shared"
    "no-tests"
  ]
  ++ on (platform.os == "linux") [ "enable-ktls" ];
  make.installTarget = [
    "install_sw"
    "install_ssldirs"
    "install_man_docs" # not install_docs: the HTML copy of the same pages
  ];
  make.installFlags = [ "OPENSSLDIR=$(prefix)/etc/ssl" ];
  # c_rehash is a perl script: perl would become a runtime dependency
  phases.after."make.install" = [
    {
      name = "no-c_rehash";
      run = "rm ($c.out)/bin/c_rehash";
    }
  ];
  tests.run = false;
  buildDependencies = [ buildPkgs.perl ] ++ on (platform.abi == "msvc") [ buildPkgs.nasm ];
  tests.version = "version";
}
