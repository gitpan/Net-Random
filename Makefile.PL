use ExtUtils::MakeMaker;
WriteMakefile(
		NAME	=> 'Net::Random',
		VERSION => '1.3',
		PREREQ_PM => {
		    'LWP::UserAgent' => 0,
		}
	     );
