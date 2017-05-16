//SH uses JQuery 1.10.2

// Select only MP1
javascript:function%20ktmp1(){$('input[type="checkbox"][data-hw-phase="mp1"]').each(function(){$(this).prop("checked",true);});}ktmp1();void(0);
// Select only LP1
javascript:function%20ktlp1(){$('input[type="checkbox"][data-hw-phase="lp1"]').each(function(){$(this).prop("checked",true);});}ktlp1();void(0);
// Select MP2
javascript:function%20ktmp2(){$('input[type="checkbox"][data-hw-phase="mp2"]').each(function(){$(this).prop("checked",true);});}ktmp2();void(0);
// Select only PP1
javascript:function%20ktpp1(){$('input[type="checkbox"][data-hw-phase="pp1"]').each(function(){$(this).prop("checked",true);});}ktpp1();void(0);
// Select only None
javascript:function%20ktnone(){$('input[type="checkbox"][data-hw-phase=""]').each(function(){$(this).prop("checked",true);});}ktnone();void(0);
// Unselect All
javascript:function%20ktuall(){$('input[type="checkbox"]').each(function(){$(this).prop("checked",false);});}ktuall();void(0);
// Select PP1 & None
javascript:function%20ktph1(){$('input[type="checkbox"]').filter('[data-hw-phase=""],[data-hw-phase="pp1"]').each(function(){$(this).prop("checked",true);});}ktph1();void(0);
// Version (improve: preserve other querystring parameters)
javascript:function%20ktver(){var%20v=prompt('Revision:','');if(v)window.location=document.URL.split('?')[0]+'?version='+v;}ktver();void(0);

// recovery distributions
javascript:function%20ktrd(){$('input[type="checkbox"]').filter('[name="recovery_makedist_release_package_config_ids[]"]').each(function(){$(this).prop("checked",true);});}ktrd();void(0);
// priamry distributions
javascript:function%20ktrd(){$('input[type="checkbox"]').filter('[name="primary_makedist_release_package_config_ids[]"]').each(function(){$(this).prop("checked",true);});}ktrd();void(0);
// all distributions
javascript:function%20ktad(){$('input[type="checkbox"]').filter('[name$="_makedist_release_package_config_ids[]"]').each(function(){$(this).prop("checked",true);});}ktad();void(0);

// all packages
javascript:function%20ktap(){$('input[type="checkbox"]').filter('[name="release_config_ids[]"]').each(function(){$(this).prop("checked",true);});}ktap();void(0);

// select package target
javascript:function%20krar(){$("td:contains('Assert')").parent().children().children('[id^="release_config_"]').each(function(){$(this).prop("checked",true);});}krar();void(0);
javascript:function%20krnar(){$("td:contains('Non-assert')").parent().children().children('[id^="release_config_"]').each(function(){$(this).prop("checked",true);});}krnar();void(0);
javascript:function%20krsar(){$("td:contains('Signable assert')").parent().children().children('[id^="release_config_"]').each(function(){$(this).prop("checked",true);});}krsar();void(0);

// select distro targets
javascript:function%20kdar(){$("td:contains('Assert')").parent().children().children('[id^="release_package_config_"]').each(function(){$(this).prop("checked",true);});}kdar();void(0);
javascript:function%20kdnar(){$("td:contains('Non-assert')").parent().children().children('[id^="release_package_config_"]').each(function(){$(this).prop("checked",true);});}kdnar();void(0);
javascript:function%20kdsar(){$("td:contains('Signable assert')").parent().children().children('[id^="release_package_config_"]').each(function(){$(this).prop("checked",true);});}kdsar();void(0);

// select all targets
javascript:function%20kaar(){$("td:contains('Assert')").parent().children().children('[class="release-release-new-checkbox"]').each(function(){$(this).prop("checked",true);});}kaar();void(0);
javascript:function%20kanar(){$("td:contains('Non-assert')").parent().children().children('[class="release-release-new-checkbox"]').each(function(){$(this).prop("checked",true);});}kanar();void(0);
javascript:function%20kasar(){$("td:contains('Signable assert')").parent().children().children('[class="release-release-new-checkbox"]').each(function(){$(this).prop("checked",true);});}kasar();void(0);

// search for a string in columns 2-3 and select
javascript:function ktsrch() {
	    var srchstr=prompt('Search string:');
	    if (srchstr) {
		$("td:nth-child(n+2):nth-child(-n+3):contains('"+srchstr+"')").parent().children().children('[class="release-release-new-checkbox"]').each(
		    function() {
			$(this).prop("checked",true);
		    }
		);
	    }
	};
    ktsrch();
    void(0);



javascript:function%20ka(){
    $("td:contains('Assert')").has(
        function(){
            return (/Assert release/).test($(this).text())
        }).filter('input[type="checkbox"],[name$="_makedist_release_package_config_ids[]"]').each(function(){$(this).prop("checked",true);});}ka();void(0);alert("hi");


//full
javascript:function ktver(){
    var d=document,l=d.location,v=null;
    v=prompt('Revision:');
    if(v)
        window.location=l.split('?')[0]+'?version='+v;
}
ktver();void(0);

// querystring parameter
var qs = (function(a) {
    if (a == "") return {};
    var b = {};
    for (var i = 0; i < a.length; ++i)
    {
        var p=a[i].split('=', 2);
        if (p.length == 1)
            b[p[0]] = "";
        else
            b[p[0]] = decodeURIComponent(p[1].replace(/\+/g, " "));
    }
    return b;
})(window.location.search.substr(1).split('&'));





<tr>
  <td align="center" valign="middle" >
      P:
      <input class="release-release-new-checkbox" data-hw-phase="lp1" id="release_package_config_908" name="primary_makedist_release_package_config_ids[]" type="checkbox" value="908" />
  </td>

  <td align="center" valign="middle" >
      R:
      <input class="release-release-new-checkbox" data-hw-phase="lp1" id="release_package_config_909" name="recovery_makedist_release_package_config_ids[]" type="checkbox" value="909" />

  </td>
  
  <td style=" background-color:#D0D0D0;">maverickhidw_ofax_dist</td>
  <td style=" background-color:#D0D0D0;">lp1</td>
  <td style=" background-color:#D0D0D0;">003</td>
  <td style=" background-color:#F0F0F0;">Assert release</td>
  <td style=" background-color:#D0D0D0;">sirius_dist</td>
  <td style=" background-color:#D0D0D0;">z_rb_triptane_limtane_3_0_1609_160222_195233</td>
</tr>



  <tr>
    <td>
      <input class="release-release-new-checkbox" data-hw-phase="mp2" id="release_config_5162" name="release_config_ids[]" type="checkbox" value="5162" />
    </td>

    <td style=" background-color:#D0D0D0;">triptane_engine_minus</td>
    <td style=" background-color:#D0D0D0;">mp2</td>
    <td style=" background-color:#D0D0D0;">002</td>
    <td style=" background-color:#F0F0F0;">Assert release</td>
    <td style=" background-color:#F0F0F0;"></td>
    <td style=" background-color:#D0D0D0;">sirius</td>
    <td style=" background-color:#D0D0D0;">z_rb_triptane_limtane_3_0_1609_160222_195200</td>
  </tr>
