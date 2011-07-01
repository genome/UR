=======================

* * *

UR is distributed as a debian package.  First add The Genome Institute's repository and key:

<p class='terminal' markdown='1'>
sudo apt-add-respository "deb http://apt.genome.wustl.edu lucid-genome main"<br/>
wget http://apt.genome.wustl.edu/ubuntu/files/genome-center.asc | sudo apt-key add<br/>
sudo apt-get update<br/>
</p>

And install UR:

<p class='terminal' markdown='1'>
sudo apt-get install libur-perl
</p>

It is also availabe from [CPAN](http://search.cpan.org/search?mode=all&query=UR).
