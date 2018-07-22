#!/usr/bin/perl
use strict;
use warnings;
use Asterisk::AMI;
use Data::Dumper;
use CGI;
use Time::Seconds;
use Time::Local;
use POSIX qw(strftime);
my $line;
my $dline       = "";
my $calldetails = "";
my $nowtime     = time;    # or any other epoch timestamp
my ( $sec, $min, $hour, $day, $month, $year ) =
  ( localtime($nowtime) )[ 0, 1, 2, 3, 4, 5 ];
my $begintime = timelocal( 0, 0, 0, $day, $month, $year );
my %repcalls;
my %reptime;
my $person;
my $totcalls    = 0;
my $tottime     = 0;
my $totwait     = 0;
my $details     = "";
my $inuse       = 0;
my $notinuse    = 0;
my $loggedin    = 0;
my $callwait    = 0;
my $callwaitstr = "";
my $topline     = "";
my $calls;
my $goodcalls = 0;
my $waitcp    = 0;
my $sl;
my $dsl;
my $slcolor;
my $abandon;
my $q;
my $queuename;
my $totabandon     = 0;
my $totabandon30   = 0;
my $totabandontime = 0;
my $avgabandontime;
####  Read the Queue file and collect stats

open( FILE, "</var/log/asterisk/queue_log" ) || die("can't open");
my @lines = reverse <FILE>;

foreach $line (@lines) {
    if ( ( $line =~ /\|1001\|/ ) ) {
        if ( $line =~ /COMPLETE/ ) {
            my ( $starttime, $endtime, $queue, $rep, $status, $wait, $calltime )
              = split /\|/, $line;
            $waitcp = $wait;
            if ( $waitcp <= 30 ) {
                $goodcalls++;
            }
            if ( $starttime < $begintime ) { last; }
            if ( not exists( $repcalls{$rep} ) ) {
                $repcalls{$rep} = 1;
                $reptime{$rep}  = $calltime;
            }
            else {
                $repcalls{$rep} = $repcalls{$rep} + 1;
                $reptime{$rep}  = $reptime{$rep} + $calltime;
            }

            $totwait = $totwait + $wait;
            $tottime = $tottime + $calltime;
            $totcalls++;
        }
        if ( $line =~ /ABANDON/ ) {
            my ( $starttime, $endtime, $queue, $rep, $status, $initqueuepos,
                $abandqueuepos, $aband )
              = split /\|/, $line;
            if ( $aband <= 30 ) {
                $totabandon30++;
            }
            $totabandon++;
            $totabandontime = $totabandontime + $aband;

        }
    }
}
my @reps = keys %repcalls;

#####  Collect per agent stats from Queue log

foreach $person (@reps) {
    my $avg = $reptime{$person} / $repcalls{$person};
    $avg = strftime( "\%M:\%Ss", gmtime($avg) );
    $details = $details
      . "<tr id = 'employee-activity'><td>$person</td><td>$avg</td><td>$repcalls{$person}</td> </tr>\n ";

}
##### Collect data from CLI
my $x;
$x = 0;
my %response;
my $astman = Asterisk::AMI->new(
    PeerAddr => '127.0.0.1',
    PeerPort => '5038',
    Username => 'admin',
    Secret   => 'd028b6b4ec2003e6558c954edd7effb9'
);

die "Unable to connect to asterisk" unless ($astman);
my $actionid =
  $astman->send_action( { Action => 'Command', Command => 'queue show 1001' } );
my $response = $astman->get_response($actionid);
my $lines    = Dumper($response);
my @parts    = split( /\n/, $lines );
foreach my $line (@parts) {
    chop($line);
    $x++;
    $line =~ tr/'//d;
    if ( $line =~ /\d+ has/ ) {
        $line =~ /\d+/;
        $q = $&;
        if ( $q == "1001" ) { $queuename = "Call Center"; }
        $' =~ /\d+/;
        $callwait = $&;
        $' =~ /\d+/;
        my $hold = $&;
        $' =~ /\d+/;
        $' =~ /\d+/;
        $' =~ /\d+/;
        $calls = $&;
        $' =~ /\d+/;
        $abandon = $&;
        $' =~ /\d.+\d%/;
        $sl = $&;

        if ( $callwait == 0 ) {
            $callwaitstr = "<td bgcolor='#00FF00'>$callwait</td>";
        }
        if ( $callwait == 1 ) {
            $callwaitstr = "<td bgcolor='#FFFF00'>$callwait</td>";
        }
        if ( $callwait > 1 ) {
            $callwaitstr = "<td bgcolor='#FF0000'>$callwait</td>";
        }
        $totwait = strftime( "\%M:\%Ss", gmtime( $totwait / $totcalls ) );
        $tottime = strftime( "\%M:\%Ss", gmtime( $tottime / $totcalls ) );
        my $inusectr =
          $inuse . "/" . sprintf( "%d", ( int($inuse) + int($notinuse) ) );
        $topline =
"<tr><td>$q</td>$callwaitstr<td>$totwait</td><td>$tottime</td><td>$calls</td><td>$abandon</td><td>dummy Abandon Time</td><td>$inusectr</td><td>$sl</td></tr>";
    }
    else {
        if ( $line =~ /calls/ ) {
            $dline = $line;
            $dline =~ /\(.+dynamic\)/;
            $dline = "$`$'";
            if ( $dline =~ /\(In use\)|\(in call\)|\(Ringing\)/ ) {
                $dline = "<tr><td colspan='7' bgcolor='#ff7777'>$`$'</td></tr>";
                $inuse++;
            }
            if ( $dline =~ /\(Not in use\)/ ) {
                $dline = "<tr><td colspan='7' bgcolor='#77FF77'>$`$'</td></tr>";
                $notinuse++;
            }
        }
        else {
            $line =~ /\d+/;
            my $callerstr = $&;
            $line =~ /wait.+\,/;
            my $nextpart = $&;
            chop $nextpart;
            $callerstr = $callerstr . " " . $nextpart;
            $dline     = "<tr><td colspan='7'>$callerstr</td></tr>";
        }
    }
    if ( $line =~ /VAR1/ )    { $dline = ""; }
    if ( $line =~ /CMD/ )     { $dline = ""; }
    if ( $line =~ /\]/ )      { last; }
    if ( $line =~ /Members/ ) { $dline = ""; }
    $calldetails = $calldetails . $dline;
    $dline       = "";

    #if ($x == 3){ last;}
}

####  PRINT HTML
my $query = CGI->new;
print $query->header();
$loggedin = $inuse + $notinuse;

#my $inusectr = $inuse . "/" . sprintf( "%d", ( int($inuse) + int($notinuse) ) );
if ( $totabandon > 0 ) {
    $avgabandontime = $totabandontime / $totabandon;
}
else { $avgabandontime = 0 }
my $avgabandstring = strftime( "\%M:\%Ss", gmtime($avgabandontime) );
my $abandonrate = "";
if ( $totcalls != 0 ) {
    $abandonrate = sprintf( "%d%%", ( $totabandon / $totcalls ) * 100 );
    $sl = sprintf( "%.1f%%",
    ( $goodcalls + $totabandon30 ) / ( $totcalls + $totabandon ) * 100 );
    $dsl = sprintf( "%.1d",
    ( $goodcalls + $totabandon30 ) / ( $totcalls + $totabandon ) * 100 );

}
else {
    $abandonrate = "N/A";
    $sl = "N/A";
}

if ( $dsl >= 75.0 ) {
    $slcolor = '"color: #00FF00;"';
}
elsif ( $dsl >= 50.0 && $sl < 75.0 ) {
    $slcolor = '"color: #FFD700;"';
}
else {
    $slcolor = '"color: #FF0000;"';
}

#$topline =
#"<tr><td>$queuename</td>$callwaitstr<td>$totwait</td><td>$tottime</td><td>$calls</td><td>$totabandon</td><td>$avgabandstring</td><td>$inusectr</td><td>$sl</td></tr>";

#print $topline;
#print $calldetails;
#print $details;
#print "</table></body></html>";
print <<EOF;
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="X-UA-Compatible" content="ie=edge">
    <meta http-equiv="refresh" content="15">
    <title>Dashboard</title>
    <link rel="stylesheet" href="/dashboard/style.css">
    <link rel="stylesheet" href="/dashboard/fontawesome-free-5.1.0-web/css/all.css">
    <link rel="stylesheet" href="/dashboard/normalize.min.css">
    <link rel="stylesheet" href="/dashboard/Activity-Summary/css/activityStyle.css">
    <link rel="stylesheet" href="/dashboard/Group-Statistics/css/statisticsStyle.css">
    <link rel="stylesheet" href="/dashboard/Dashboard/css/dashboardStyle.css">
    <link rel="stylesheet" href="/dashboard/barGraph/css/graphStyle.css">
</head>
<body>
    <table >
        <tr>
            <!-- ACTIVITY SUMMARY -->
            <td id = "main-cell" height = "400" width = "725">
                <div id="graph">
                    <main>
                        <h3 id = "caption"><img class = "image" src = "/dashboard/images/Call-Statistics.png" alt = "Call Statistics"> Call Statistics</h3>
                        <section>
                        <ul class="style-1">
                            <li>
                                <em>Total Calls</em>
                                <span>$totcalls</span>
                            </li>
                            <li>
                                <em>Abandoned</em>
                                <span>$totabandon</span>
                            </li>
                            <li>
                                <em>Waiting</em>
                                <span>$callwait</span>
                            </li>
                        </ul>
                        </section>
                    </main>
                <script src="/dashboard/jquery.min.js"></script>
                <script  src="/dashboard/barGraph/js/barGraph.js"></script>
                </div>
            </td>
            <!-- DASHBOARD -->
            <td id = "main-cell" height = "400" width = "725">
                <div id="dashboard">
                    <table>
                        <tr>
                            <caption id = "caption"><b>Dashboard</b></caption>
                        </tr>
                        <div class = "content">
                            <tr id = "header-caption">
                                <td><img class = "image" src = "/dashboard/images/Logged-In.png" alt = "Logged In"></i></td>
                                <td class = "caption-dashboard">Logged In</td>
                                <td class = "number-dashboard">$loggedin</td>
                            </tr>
                            <tr>
                                <td><img class = "image" src = "/dashboard/images/Available.png" alt = "Available"></i></td>
                                <td class = "caption-dashboard">Available</td>
                                <td class = "number-dashboard">$notinuse</td>
                            </tr>
                            <tr>
                                <td><img class = "image" src = "/dashboard/images/On-Call.png" alt = "On Call"></td>
                                <td class = "caption-dashboard">On Call</td>
                                <td class = "number-dashboard">$inuse</td>
                            </tr>
                        </div>
                    </table>
                </div>
            </td>
        </tr>
        <tr>
            <!-- GROUP STATISTICS -->
            <td id = "main-cell" height = "400" width = "725">
                <div id="group-statistics">
                    <table>
                        <tr>
                            <caption id = "caption"><b>Group Statistics</b></caption>
                        </tr>
                        <div class = "content">
                            <tr id = "service-level">
                                <th rowspan = "4"><img class = "image" src = "/dashboard/images/Service-Level.png" alt = "Service Level"><span class = "service-level-percent" style = $slcolor> $sl</span><p id = "service-level-text">Service Level</p></th>
                            </tr>
                            <tr>
                                <td><img class = "image" src = "/dashboard/images/Average-Speed-to-Answer.png" alt = "Average Speed to Answer"><span class = "time">$totwait</span><p id = "caption-time">Average Speed Answer</p></td>
                                <td><img class = "image" src = "/dashboard/images/Average-Call-Duration.png" alt = "Average Call Duration"><span class = "time">$tottime</span><p id = "caption-time">Average Call Duration</p></td>
                            </tr>
                            <tr>
                                <td><img class = "image" src = "/dashboard/images/Average-Abandonment-Time.png" alt = "Average Abandonment Time"><span class = "time">$avgabandstring</span><p id = "caption-time">Average Abandonment Time</p></td>
                                <td><img class = "image" src = "/dashboard/images/Abandonment-Rate.png" alt = "Abandonment Rate"><span class = "time">$abandonrate</span><p id = "caption-time">Abandonment Rate</p></td>
                            </tr>
                            
                        </div>
                    </table>
                </div>
            </td>
            <!-- GRAPH -->
            <td id = "main-cell" height = "400" width = "725">
                <div id="activity">
                    <table>
                        <tr>
                            <caption id = "caption-activity"><b>Activity Summary</b></caption>
                        </tr>
                        <div class = "content">
                            <tr id = "header-activity" height = "46"> 
                                <th>Agent Name</th>
                                <th>Average Call Time</th> 
                                <th>Number of Calls</th>
                            </tr>
			    $details
                        </div>
                    </table>   
                </div>

            </td>
        </tr>
    </table>
</body>
</html>
EOF
