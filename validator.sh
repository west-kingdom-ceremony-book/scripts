#! /bin/sh

# Uses epubcheck, a java based epub validator
# https://github.com/IDPF/epubcheck/releases
# unzip the release; update this script
# to point to the correct jar file for your release


 java -jar  ../epubcheck-3.0.1/epubcheck-3.0.1.jar  "$@"
 
