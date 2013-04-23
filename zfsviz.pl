#!/bin/perl

# ZFSviz v 0.002
# 
# Copyright 2009 by the people mentioned under "Developers" in the README.
# Point of Contact: http://www.c0t0d0s0.org/pages/zfsviz.html
# This application is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

use lib "./modules";
use Tree::Simple;
use Getopt::Std;

#Get command line options
getopt("mosvfa7:");
$verbose ="true" if $opt_m eq "verbose";
$verbose ="false" if $opt_m eq "basic";
$output_file = $opt_o;
$output_file = "out.dot" if $output_file eq "";
$print_autosnapshot = "false";
$print_autosnapshot = "true" if $opt_a eq "show";
if ($verbose eq "true") {
	$volume_verbose_list = $opt_v;
	$volume_verbose_list = "type" if $opt_v eq "";
	@volume_verbose_array = split(/\,/,$volume_verbose_list);
	$snapshot_verbose_list = $opt_s; 
	$snapshot_verbose_list = "type" if $opt_s eq "";
	@snapshot_verbose_array = split(/\,/,$snapshot_verbose_list);
	$filesystem_verbose_list = $opt_f;
	$filesystem_verbose_list = "type" if $opt_f eq "";
	@filesystem_verbose_array = split(/\,/,$filesystem_verbose_list);
}

if ($opt_7 ne "") {
 $s7000mode = "true";
 ($username,$host) = $opt_7 =~ /(.*)\@(.*)$/;
}

#Initialisation
my @metadata;
my $kernelversion=`uname -r`;
chomp($kernelversion);
my $tree = Tree::Simple->new("root");
open(OUT,">$output_file");

# Check for Solaris Version and choose correct ZFS commands 
$zfslist_command = "zfs list -H -t all -o name,origin,type" if $kernelversion eq "5.11";
$zfslist_command = "zfs list -H -o name,origin,type" if $kernelversion eq "5.10";
$zfslist_command = "ssh -l $username $host \< s7000scripts/zfslist.aksh" if $s7000mode eq "true"; 

#Gathering filesystemnames and basic informations for further processing
open(ZFS,"$zfslist_command|");
while(<ZFS>) {
	$line=$_;
	next if $line=~/^$/;
	chomp($line);
	if ($line =~ /^\#\#\#ZFSLIST/) {
		push(@s7000_zfslist,$line);
		next;
	}
 	($objectname,$origin,$type) = $line =~ /^(\S*)\s*(\S*)\s*(\S*)$/;
	$filesystemdata{$objectname} = { origin => "$origin", type => "$type"} 
}

if ($s7000mode eq "true") {
 	foreach $s7000_zfslist_iterator (@s7000_zfslist) {
		my $metadataline = $s7000_zfslist_iterator;
		($metadataindex,$rest) = $metadataline =~ /\#\#\#ZFSLIST\#\#\#(.*)\#\#\#(.*)$/;
		$metadataindex =~ s/\//\|\|/gi;
		$metadataindex =~ s/\@/\|\|/gi;
		$metadataindex = $metadataindex . "\|\|";
		($var,$value) = split(/ \= /,$rest);
		$var =~ s/ //gi;
		next if $var eq '';
		$var = lc($var);
		$metadata{$metadataindex}{$var} = "$value";
	}
} 

#Processing of the data and gathering further filesystem informations
foreach $i (sort keys %filesystemdata) {
        if ($print_autosnapshot ne "true") {
		next if $i=~/zfs-auto-snap/;
	}
	my $metadataindex = $i;
	$metadataindex =~ s/\//\|\|/gi;
	$metadataindex =~ s/\@/\|\|/gi;
	$metadataindex = $metadataindex . "\|\|";
	if ($filesystemdata{$i}{type} eq "snapshot") {
		($rest,$snapshotname) = split(/\@/,$i);
		$snapshotname = "$snapshotname";
  		@directorystructure = split(/\//,$rest);
  		tinsert($tree,@directorystructure,$snapshotname);
 	} 
 	if ($filesystemdata{$i}{type} eq "filesystem") {
  		@directorystructure = split(/\//,$i);
  		tinsert($tree,@directorystructure);
 	} 
 	if ($filesystemdata{$i}{type} eq "volume") {
  		@directorystructure = split(/\//,$i);
 		tinsert($tree,@directorystructure);
 	}
	if ($filesystemdata{$i}{type} eq "project") {
  		@directorystructure = split(/\//,$i);
 		tinsert($tree,@directorystructure);
 	}
	if ($s7000mode ne "true") {
  		open(ZFSGET,"zfs get -H -o property,value all $i |");
  		while(<ZFSGET>) {
   			$zfsgetline=$_;
   			chomp($zfsgetline);
   			(my $property,my $valueofproperty) = $zfsgetline =~ /(\S*?)\s(.*)/;
   			$property=lc($property);
   			$metadata{$metadataindex}{$property} = "$valueofproperty";
		}
		close(ZFSGET);
  	} 	
	if ($s7000mode eq "true") {
		$metadata{$metadataindex}{type}=$filesystemdata{$i}{type};
	}
}

print OUT "digraph ZFS \{\n";
tprint($tree);
print OUT "}\n";

# Insert a list into a tree
sub tinsert
{
	my $tree = shift;
	return $tree unless scalar @_;

	my $el = shift;
	my @rest = @_;
	my @match = grep { $_->getNodeValue() eq $el}  $tree->getAllChildren();

	if (scalar @match) {
		my $t = $match[0];
		tinsert($t, @rest);
	} else {
		tinsert($tree->addChild(Tree::Simple->new($el)), $el, @rest);
	}
}

# Print tree node
sub print_nodeobjects
{
	my $tree = shift;
        my $nodedepth;
        my $nodevalue;
        my $type;
        my $nodeobjectname;
	my $colorofnode;
        $nodevalue = $tree->getNodeValue();
        $nodedepth = $tree->getDepth();
        $curnode[$nodedepth] = $nodevalue;
        for ($currentpos_iterator=0; $currentpos_iterator <= $nodedepth; $currentpos_iterator++) {
	         $currentposition= $currentposition . $curnode[$currentpos_iterator] ."\|\|";
	}        
	if ($metadata{$currentposition}{type} eq "snapshot") {
	         $colorofnode="blue";
		 $shapeofnode="ellipse";
		 if ($verbose eq "true") {
		 	foreach $properties_to_display_iterator (@snapshot_verbose_array) {
				$properties_to_display = $properties_to_display . "\{$properties_to_display_iterator\|$metadata{$currentposition}{$properties_to_display_iterator}\}|";
			}
		}
	}

	if ($metadata{$currentposition}{type} eq "filesystem") {
         	$colorofnode="black";
	 	$shapeofnode="box";
	 	if ($verbose eq "true") {
	 		foreach $properties_to_display_iterator (@filesystem_verbose_array) {
				$properties_to_display = $properties_to_display . "\{$properties_to_display_iterator\|$metadata{$currentposition}{$properties_to_display_iterator}\}|";
			}
		}
	}

	if ($metadata{$currentposition}{type} eq "project") {
         	$colorofnode="orange";
	 	$shapeofnode="box";
	 	if ($verbose eq "true") {
	 		foreach $properties_to_display_iterator (@filesystem_verbose_array) {
				$properties_to_display = $properties_to_display . "\{$properties_to_display_iterator\|$metadata{$currentposition}{$properties_to_display_iterator}\}|";
			}
		}
	}

        if ($metadata{$currentposition}{type} eq "volume") { 
         	$colorofnode="green";
	 	$shapeofnode="hexagon";
	 	if ($verbose eq "true") {
	 		foreach $properties_to_display_iterator (@volume_verbose_array) {
				$properties_to_display = $properties_to_display . "\{$properties_to_display_iterator\|$metadata{$currentposition}{$properties_to_display_iterator}\}|";
			}
		}
	}
        print "$nodevalue $currentposition\n";
	if ($verbose eq "true") {
		chop($properties_to_display);
         	print OUT " \"" . $currentposition . "\"[color=$colorofnode,shape=record,label=\"\{$nodevalue\|$properties_to_display\}\"] \n";
        } else {
		print OUT " \"" . $currentposition . "\"[color=$colorofnode,shape=$shapeofnode,label=\"$nodevalue\"] \n"
	}
        $currentposition="";
	$properties_to_display="";
}

sub print_edges
{
	my $tree = shift;
        my $nodevalue;
        my $type;
        my $nodeobjectname;
        $nodevalue = $tree->getNodeValue();
	my $parent = $tree->getParent;
        my $parentvalue = $parent->getNodeValue();
        $nodedepth = $tree->getDepth();
        $curnode[$nodedepth] = $nodevalue;
        for ($currentpos_iterator=0; $currentpos_iterator <= $nodedepth; $currentpos_iterator++) {
		$currentposition= $currentposition . $curnode[$currentpos_iterator] ."\|\|";
	}
        for ($parentpos_iterator=0; $parentpos_iterator < $nodedepth; $parentpos_iterator++) {
	        $parentposition = $parentposition . $curnode[$parentpos_iterator] ."\|\|";
	}
        print OUT " \"" . $parentposition . "\"-\>\"" . $currentposition . "\"\n";
        if ($metadata{$currentposition}{origin} ne "") {
 		$clonemaster = $metadata{$currentposition}{origin};
		$clonemaster =~ s/\//\|\|/gi;
 		$clonemaster =~ s/\@/\|\|/gi;
 		$clonemaster = $clonemaster . "\|\|";
		print OUT " \"" . $currentposition . "\"-\>\"" . $clonemaster . "\"[color=red,label=\"is a clone\\n based on\"]\n";		
	}
        $currentposition="";
	$parentposition="";
	$clonemaster="";
}

# Print the whole tree
sub tprint
{
	my $tree = shift;
	$tree->traverse(\&print_nodeobjects);
	$tree->traverse(\&print_edges);
}
