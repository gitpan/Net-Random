use ExtUtils::MakeMaker;
WriteMakefile(
		NAME	=> 'Net::Random',
		VERSION => '1.0',
		PREREQ_PM => {
		    'LWP::UserAgent' => 0,
		    Config           => 0,
		}
	     );
