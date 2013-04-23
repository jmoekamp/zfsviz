# AUTHOR 
# Stevan Little, <stevan@iinteractive.com>
# Rob Kinyon, <rob@iinteractive.com>
#
# COPYRIGHT AND LICENSE 
#
# Copyright 2004-2006 by Infinity Interactive, Inc.
# http://www.iinteractive.com
# This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

package Tree::Simple;

use 5.006;

use strict;
use warnings;

our $VERSION = '1.18';

use Scalar::Util qw(blessed);
#require "scalarutilpp.pm";
#import scalarutilpp;

## ----------------------------------------------------------------------------
## Tree::Simple
## ----------------------------------------------------------------------------

my $USE_WEAK_REFS;

sub import {
    shift;
    return unless @_;
    if (lc($_[0]) eq 'use_weak_refs') {
        $USE_WEAK_REFS++;
        *Tree::Simple::weaken = \&Scalar::Util::weaken;
    }
}

## class constants
use constant ROOT => "root";

### constructor

sub new {
    my ($_class, $node, $parent) = @_;
    my $class = ref($_class) || $_class;
    my $tree = bless({}, $class);
    $tree->_init($node, $parent, []);  
    return $tree;
}

### ---------------------------------------------------------------------------
### methods
### ---------------------------------------------------------------------------

## ----------------------------------------------------------------------------
## private methods

sub _init {
    my ($self, $node, $parent, $children) = @_;
    # set the value of the unique id
    ($self->{_uid}) = ("$self" =~ /\((.*?)\)$/);
    # set the value of the node
    $self->{_node} = $node;
    # and set the value of _children
    $self->{_children} = $children;    
    $self->{_height} = 1;
    $self->{_width} = 1;
    # Now check our $parent value
    if (defined($parent)) {
        if (blessed($parent) && $parent->isa("Tree::Simple")) {
            # and set it as our parent
            $parent->addChild($self);
        }
        elsif ($parent eq $self->ROOT) {
            $self->_setParent( $self->ROOT );
        }
        else {
            die "Insufficient Arguments : parent argument must be a Tree::Simple object";
        }
    }
    else {
        $self->_setParent( $self->ROOT );
    }
}

sub _setParent {
    my ($self, $parent) = @_;
    (defined($parent) && 
        (($parent eq $self->ROOT) || (blessed($parent) && $parent->isa("Tree::Simple"))))
        || die "Insufficient Arguments : parent also must be a Tree::Simple object";
    $self->{_parent} = $parent;    
    if ($parent eq $self->ROOT) {
        $self->{_depth} = -1;
    }
    else {
        weaken($self->{_parent}) if $USE_WEAK_REFS;    
        $self->{_depth} = $parent->getDepth() + 1;
    }
}

sub _detachParent {
    return if $USE_WEAK_REFS;
    my ($self) = @_;
    $self->{_parent} = undef;
}

sub _setHeight {
    my ($self, $child) = @_;
    my $child_height = $child->getHeight();
    return if ($self->{_height} >= $child_height + 1);
    $self->{_height} = $child_height + 1;
    
    # and now bubble up to the parent (unless we are the root)
    $self->getParent()->_setHeight($self) unless $self->isRoot();
}

sub _setWidth {
    my ($self, $child_width) = @_;
    if (ref($child_width)) {
        return if ($self->{_width} > $self->getChildCount());    
        $child_width = $child_width->getWidth();
    }
    $self->{_width} += $child_width;
    # and now bubble up to the parent (unless we are the root)
    $self->getParent()->_setWidth($child_width) unless $self->isRoot();            
}

## ----------------------------------------------------------------------------
## mutators

sub setNodeValue {
    my ($self, $node_value) = @_;
    (defined($node_value)) || die "Insufficient Arguments : must supply a value for node";
    $self->{_node} = $node_value;
}

sub setUID {
    my ($self, $uid) = @_;
    ($uid) || die "Insufficient Arguments : Custom Unique ID's must be a true value";
    $self->{_uid} = $uid;
}

## ----------------------------------------------
## child methods

sub addChild {
    splice @_, 1, 0, $_[0]->getChildCount;
    goto &insertChild;
}

sub addChildren {
    splice @_, 1, 0, $_[0]->getChildCount;
    goto &insertChildren;
}

sub _insertChildAt {
    my ($self, $index, @trees) = @_;

    (defined($index)) 
        || die "Insufficient Arguments : Cannot insert child without index";

    # check the bounds of our children 
    # against the index given
    my $max = $self->getChildCount();
    ($index <= $max)
        || die "Index Out of Bounds : got ($index) expected no more than (" . $self->getChildCount() . ")";

    (@trees) 
        || die "Insufficient Arguments : no tree(s) to insert";    

    foreach my $tree (@trees) {
        (blessed($tree) && $tree->isa("Tree::Simple")) 
            || die "Insufficient Arguments : Child must be a Tree::Simple object";    
        $tree->_setParent($self);
        $self->_setHeight($tree);   
        $self->_setWidth($tree);                         
        $tree->fixDepth() unless $tree->isLeaf();
    }

    # if index is zero, use this optimization
    if ($index == 0) {
        unshift @{$self->{_children}} => @trees;
    }
    # if index is equal to the number of children
    # then use this optimization    
    elsif ($index == $max) {
        push @{$self->{_children}} => @trees;
    }
    # otherwise do some heavy lifting here
    else {
        splice @{$self->{_children}}, $index, 0, @trees;
    }

    $self;
}

*insertChildren = \&_insertChildAt;

# insertChild is really the same as insertChildren, you are just
# inserting an array of one tree
*insertChild = \&insertChildren;

sub removeChildAt {
    my ($self, $index) = @_;
    (defined($index)) 
        || die "Insufficient Arguments : Cannot remove child without index.";
    ($self->getChildCount() != 0) 
        || die "Illegal Operation : There are no children to remove";        
    # check the bounds of our children 
    # against the index given        
    ($index < $self->getChildCount()) 
        || die "Index Out of Bounds : got ($index) expected no more than (" . $self->getChildCount() . ")";        
    my $removed_child;
    # if index is zero, use this optimization    
    if ($index == 0) {
        $removed_child = shift @{$self->{_children}};
    }
    # if index is equal to the number of children
    # then use this optimization    
    elsif ($index == $#{$self->{_children}}) {
        $removed_child = pop @{$self->{_children}};    
    }
    # otherwise do some heavy lifting here    
    else {
        $removed_child = $self->{_children}->[$index];
        splice @{$self->{_children}}, $index, 1;
    }
    # make sure we fix the height
    $self->fixHeight();
    $self->fixWidth();    
    # make sure that the removed child
    # is no longer connected to the parent
    # so we change its parent to ROOT
    $removed_child->_setParent($self->ROOT);
    # and now we make sure that the depth 
    # of the removed child is aligned correctly
    $removed_child->fixDepth() unless $removed_child->isLeaf();    
    # return ths removed child
    # it is the responsibility 
    # of the user of this module
    # to properly dispose of this
    # child (and all its sub-children)
    return $removed_child;
}

sub removeChild {
    my ($self, $child_to_remove) = @_;
    (defined($child_to_remove))
        || die "Insufficient Arguments : you must specify a child to remove";
    # maintain backwards compatability
    # so any non-ref arguments will get 
    # sent to removeChildAt
    return $self->removeChildAt($child_to_remove) unless ref($child_to_remove);
    # now that we are confident it's a reference
    # make sure it is the right kind
    (blessed($child_to_remove) && $child_to_remove->isa("Tree::Simple")) 
        || die "Insufficient Arguments : Only valid child type is a Tree::Simple object";
    my $index = 0;
    foreach my $child ($self->getAllChildren()) {
        ("$child" eq "$child_to_remove") && return $self->removeChildAt($index);
        $index++;
    }
    die "Child Not Found : cannot find object ($child_to_remove) in self";
}

sub getIndex {
    my ($self) = @_;
    return -1 if $self->{_parent} eq $self->ROOT;
    my $index = 0;
    foreach my $sibling ($self->{_parent}->getAllChildren()) {
        ("$sibling" eq "$self") && return $index;
        $index++;
    }
}

## ----------------------------------------------
## Sibling methods

# these addSibling and addSiblings functions 
# just pass along their arguments to the addChild
# and addChildren method respectively, this 
# eliminates the need to overload these method
# in things like the Keyable Tree object

sub addSibling {
    my ($self, @args) = @_;
    (!$self->isRoot()) 
        || die "Insufficient Arguments : cannot add a sibling to a ROOT tree";
    $self->{_parent}->addChild(@args);
}

sub addSiblings {
    my ($self, @args) = @_;
    (!$self->isRoot()) 
        || die "Insufficient Arguments : cannot add siblings to a ROOT tree";
    $self->{_parent}->addChildren(@args);
}

sub insertSiblings {
    my ($self, @args) = @_;
    (!$self->isRoot()) 
        || die "Insufficient Arguments : cannot insert sibling(s) to a ROOT tree";
    $self->{_parent}->insertChildren(@args);
}

# insertSibling is really the same as
# insertSiblings, you are just inserting
# and array of one tree
*insertSibling = \&insertSiblings;

# I am not permitting the removal of siblings 
# as I think in general it is a bad idea

## ----------------------------------------------------------------------------
## accessors

sub getUID       { $_[0]{_uid}    }
sub getParent    { $_[0]{_parent} }
sub getDepth     { $_[0]{_depth}  }
sub getNodeValue { $_[0]{_node}   }
sub getWidth     { $_[0]{_width}  }
sub getHeight    { $_[0]{_height} }

# for backwards compatability
*height = \&getHeight;

sub getChildCount { $#{$_[0]{_children}} + 1 }

sub getChild {
    my ($self, $index) = @_;
    (defined($index)) 
        || die "Insufficient Arguments : Cannot get child without index";
    return $self->{_children}->[$index];
}

sub getAllChildren {
    my ($self) = @_;
    return wantarray ?
        @{$self->{_children}}
        :
        $self->{_children};
}

sub getSibling {
    my ($self, $index) = @_;
    (!$self->isRoot()) 
        || die "Insufficient Arguments : cannot get siblings from a ROOT tree";    
    $self->getParent()->getChild($index);
}

sub getAllSiblings {
    my ($self) = @_;
    (!$self->isRoot()) 
        || die "Insufficient Arguments : cannot get siblings from a ROOT tree";    
    $self->getParent()->getAllChildren();
}

## ----------------------------------------------------------------------------
## informational

sub isLeaf { $_[0]->getChildCount == 0 }

sub isRoot {
    my ($self) = @_;
    return (!defined($self->{_parent}) || $self->{_parent} eq $self->ROOT);
}

sub size {
    my ($self) = @_;
    my $size = 1;
    foreach my $child ($self->getAllChildren()) {
        $size += $child->size();    
    }
    return $size;
}

## ----------------------------------------------------------------------------
## misc

# NOTE:
# Occasionally one wants to have the 
# depth available for various reasons
# of convience. Sometimes that depth 
# field is not always correct.
# If you create your tree in a top-down
# manner, this is usually not an issue
# since each time you either add a child
# or create a tree you are doing it with 
# a single tree and not a hierarchy.
# If however you are creating your tree
# bottom-up, then you might find that 
# when adding hierarchies of trees, your
# depth fields are all out of whack.
# This is where this method comes into play
# it will recurse down the tree and fix the
# depth fields appropriately.
# This method is called automatically when 
# a subtree is added to a child array
sub fixDepth {
    my ($self) = @_;
    # make sure the tree's depth 
    # is up to date all the way down
    $self->traverse(sub {
            my ($tree) = @_;
            return if $tree->isRoot();
            $tree->{_depth} = $tree->getParent()->getDepth() + 1;
        }
    );
}

# NOTE:
# This method is used to fix any height 
# discrepencies which might arise when 
# you remove a sub-tree
sub fixHeight {
    my ($self) = @_;
    # we must find the tallest sub-tree
    # and use that to define the height
    my $max_height = 0;
    unless ($self->isLeaf()) {
        foreach my $child ($self->getAllChildren()) {
            my $child_height = $child->getHeight();
            $max_height = $child_height if ($max_height < $child_height);
        }
    }
    # if there is no change, then we 
    # need not bubble up through the
    # parents
    return if ($self->{_height} == ($max_height + 1));
    # otherwise ...
    $self->{_height} = $max_height + 1;
    # now we need to bubble up through the parents 
    # in order to rectify any issues with height
    $self->getParent()->fixHeight() unless $self->isRoot();
}

sub fixWidth {
    my ($self) = @_;
    my $fixed_width = 0;
    $fixed_width += $_->getWidth() foreach $self->getAllChildren();
    $self->{_width} = $fixed_width;
    $self->getParent()->fixWidth() unless $self->isRoot();
}

sub traverse {
    my ($self, $func, $post) = @_;
    (defined($func)) || die "Insufficient Arguments : Cannot traverse without traversal function";
    (ref($func) eq "CODE") || die "Incorrect Object Type : traversal function is not a function";
    (ref($post) eq "CODE") || die "Incorrect Object Type : post traversal function is not a function"
        if defined($post);
    foreach my $child ($self->getAllChildren()) { 
        $func->($child);
        $child->traverse($func, $post);
        defined($post) && $post->($child);
    }
}

# this is an improved version of the 
# old accept method, it now it more
# accepting of its arguments
sub accept {
    my ($self, $visitor) = @_;
    # it must be a blessed reference and ...
    (blessed($visitor) && 
        # either a Tree::Simple::Visitor object, or ...
        ($visitor->isa("Tree::Simple::Visitor") || 
            # it must be an object which has a 'visit' method avaiable
            $visitor->can('visit')))
        || die "Insufficient Arguments : You must supply a valid Visitor object";
    $visitor->visit($self);
}

## ----------------------------------------------------------------------------
## cloning 

sub clone {
    my ($self) = @_;
    # first clone the value in the node
    my $cloned_node = _cloneNode($self->getNodeValue());
    # create a new Tree::Simple object 
    # here with the cloned node, however
    # we do not assign the parent node
    # since it really does not make a lot
    # of sense. To properly clone it would
    # be to clone back up the tree as well,
    # which IMO is not intuitive. So in essence
    # when you clone a tree, you detach it from
    # any parentage it might have
    my $clone = $self->new($cloned_node);
    # however, because it is a recursive thing
    # when you clone all the children, and then
    # add them to the clone, you end up setting
    # the parent of the children to be that of
    # the clone (which is correct)
    $clone->addChildren(
                map { $_->clone() } $self->getAllChildren()
                ) unless $self->isLeaf();
    # return the clone            
    return $clone;
}
    
# this allows cloning of single nodes while 
# retaining connections to a tree, this is sloppy
sub cloneShallow {
    my ($self) = @_;
    my $cloned_tree = { %{$self} };
    bless($cloned_tree, ref($self));    
    # just clone the node (if you can)
    $cloned_tree->setNodeValue(_cloneNode($self->getNodeValue()));
    return $cloned_tree;    
}

# this is a helper function which 
# recursively clones the node
sub _cloneNode {
    my ($node, $seen) = @_;
    # create a cache if we dont already
    # have one to prevent circular refs
    # from being copied more than once
    $seen = {} unless defined $seen;
    # now here we go...
    my $clone;
    # if it is not a reference, then lets just return it
    return $node unless ref($node);
    # if it is in the cache, then return that
    return $seen->{$node} if exists ${$seen}{$node};
    # if it is an object, then ...    
    if (blessed($node)) {
        # see if we can clone it
        if ($node->can('clone')) {
            $clone = $node->clone();
        }
        # otherwise respect that it does 
        # not want to be cloned
        else {
            $clone = $node;
        }
    }
    else {
        # if the current slot is a scalar reference, then
        # dereference it and copy it into the new object
        if (ref($node) eq "SCALAR" || ref($node) eq "REF") {
            my $var = "";
            $clone = \$var;
            ${$clone} = _cloneNode(${$node}, $seen);
        }
        # if the current slot is an array reference
        # then dereference it and copy it
        elsif (ref($node) eq "ARRAY") {
            $clone = [ map { _cloneNode($_, $seen) } @{$node} ];
        }
        # if the current reference is a hash reference
        # then dereference it and copy it
        elsif (ref($node) eq "HASH") {
            $clone = {};
            foreach my $key (keys %{$node}) {
                $clone->{$key} = _cloneNode($node->{$key}, $seen);
            }
        }
        else {
            # all other ref types are not copied
            $clone = $node;
        }
    }
    # store the clone in the cache and 
    $seen->{$node} = $clone;        
    # then return the clone
    return $clone;
}


## ----------------------------------------------------------------------------
## Desctructor

sub DESTROY {
    # if we are using weak refs 
    # we dont need to worry about
    # destruction, it will just happen
    return if $USE_WEAK_REFS;
    my ($self) = @_;
    # we want to detach all our children from 
    # ourselves, this will break most of the 
    # connections and allow for things to get
    # reaped properly
    unless (!$self->{_children} && scalar(@{$self->{_children}}) == 0) {
        foreach my $child (@{$self->{_children}}) { 
            defined $child && $child->_detachParent();
        }
    }
    # we do not need to remove or undef the _children
    # of the _parent fields, this will cause some 
    # unwanted releasing of connections. 
}

## ----------------------------------------------------------------------------
## end Tree::Simple
## ----------------------------------------------------------------------------

1;


