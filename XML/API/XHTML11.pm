    package XML::API::XHTML11;
    use strict;
    use warnings;
    use base qw(XML::API);

    our $VERSION = '0.25';

    use constant DOCTYPE =>
      qq{<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">};

    use constant XSD          => {};
    use constant ROOT_ELEMENT => 'html';
    use constant ROOT_ATTRS   => { xmlns => 'http://www.w3.org/1999/xhtml' };

    my $xsd = {};

    sub _doctype {
        return
          return qq{<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">};
    }

    sub _xsd {
        return $xsd;
    }

    sub _root_element {
        return 'html';
    }

    sub _root_attrs {
        return { xmlns => 'http://www.w3.org/1999/xhtml' };
    }

    sub _content_type {
        return 'application/xhtml+xml';
    }

    1;
