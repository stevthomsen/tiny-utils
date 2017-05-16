#!/usr/bin/perl -w

sub mydie();

mydie() if exists($ARGV[1]);
mydie() if ($ARGV[0] eq "-h" or $ARGV[0] eq "--help");

my $project = $ARGV[0];
$project =~ s/\///;

#create dir if does not exist, exit if PID has a number in it
if (opendir("./", $project)) {
    print ("$project directory exists \n");
    if ( open (PID, "./$project/$project.pid") ) {
        my @tmp = <PID>;
        close (PID);
        foreach my $lines (@tmp) {
            if ($lines =~ /\d/) {
                print ("Autotest is already running $project (.PID has a number). Cannot create. \n");
                exit(0);
            }
        }
    }
}
else {
    mkdir("./$project");
    print "Creating new test project: $project \n";
}

my $projlen  = length($project);
my $extrawhitelen = 56; #total characters
my $extrawhite = "";

#                total size     - (side buffers * 2) - (" # cd ") - (length of project name) - (spaces on either side of $extrawhite)
$extrawhitelen = $extrawhitelen - (4 * 2)            - (6)        - ($projlen)               - (2);
for (my $i = 1; $i <= $extrawhitelen; $i++) {$extrawhite .= " "}

#touch $project.keep,log,pid,startup_log,test_info.html
system ("touch ./$project/$project.keep");
print "  touch ./$project/$project.keep \n";
system ("touch ./$project/$project.log");
print "  touch ./$project/$project.log \n";
system ("touch ./$project/$project.pid");
print "  touch ./$project/$project.pid \n";
system ("touch ./$project/$project.startup_log");
print "  touch ./$project/$project.startup_log \n";
system ("touch ./$project/test_info.html");
print "  touch ./$project/test_info.html \n";
system ("mkfifo ./$project/$project.pipe");
print "  mkfifo ./$project/$project.pipe \n";
system ("ln -s ../tests_dir/usable_print ./$project/tests");
print "  ln -s ../tests_dir/usable_print ./$project/tests \n";
system ("chmod 666 ./$project/*");
print "  chmod 666 ./$project/* \n";
system ("chmod 777 ./$project/");
print "  chmod 777 ./$project/ \n";

print "\
******************************************************** \
**** Don't forget to update the \"mapping.txt\" and   **** \
**** \"settings\" files before testing new projects!  **** \
****                                                **** \
**** Also set up your tests file by running:        **** \
**** # cd $project $extrawhite **** \
**** # rm tests                                     **** \
**** # ln -s ../tests_dir/(desired test file) tests **** \
******************************************************** \
";

exit(0);

sub mydie (){
print("
new_test_folder.pl

Summary: Produces a new test folder for autotest with required
         files to begin execution.
Usage:   ./new_test_folder.pl <project_name>
Example: ./new_test_folder.pl violet

");

exit(0);
}
