    package XML::API::NCX;
    use strict;
    use warnings;
    use base qw(XML::API);

    our $VERSION = '0.25';

    use constant DOCTYPE =>
      q{<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">};

    use constant XSD          => {};
    use constant ROOT_ELEMENT => 'html';
    use constant ROOT_ATTRS   => { xmlns => 'http://www.w3.org/1999/xhtml' };

    my $xsd = {};

    sub _doctype {
        return q{<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">};
    }

    sub _xsd {
        return $xsd;
    }

    sub _root_element {
        return 'ncx';
    }

    sub _root_attrs {
        return {
                 xmlns   => "http://www.daisy.org/z3986/2005/ncx/",
                 version => "2005-1"
               };
    }

    sub _content_type {
        return 'application/x-dtbncx+xml';
    }

    1;
