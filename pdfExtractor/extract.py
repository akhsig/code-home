###################################################################
##                  DocumentContentExtractor                     ##
##  Author: Olivier Gilbert, contact: ogilbert@e-medhosting.com  ##
##              Date: May 16th, 2013.  Version: 1.1              ##
###################################################################

###################################################################
##                           Changelog                           ##
## - v0.1:                                                       ##
##     	=> script can read pdf files                             ##
## - v0.2                                                        ##
##	=> script attempts to decrypt pdf files                  ##
## - v1.0                                                        ##
## 	=> script now reads ppt, pptx, doc, docx                 ##
## - v1.1                                                        ##
##	=> script now shows progress bar                         ##
## - v2.0							 ##
##	=> script now takes full csv file and tries to find	 ##
##	   information on presentation based on name		 ##
###################################################################

# This script takes a list of pdf files (will us ls of a given directory for list of files)
# and extracts the text content of each pdf file and writes it on a new line in an output file
# If the pdf is encrypted, the script will attempt to decrypt it with the empty password
# (since we don't need to edit, this should work for most documents!)

# First import required packages
import PyPDF2 as p #must be installed for this script to work
from subprocess import check_output # needed to run shell commands
import subprocess as sp #need this for the subprocess module in general
import string as s
from pptx import Presentation #needed for pptx support!
import sys #seems to be needed for fixing problem with the try statement for pptx
import os #will be used for directory listing
import MySQLdb #needed for mysql integration

host = "192.168.0.6"
user = "ogilbert"
password = "thrhhhvthdb"
schema = "multiwebcast"

db = db=MySQLdb.connect(host=host, user=user, passwd=password, db=schema);
cursor = db.cursor()

info_query = """
	SELECT
		*
	FROM
		_40_conference
	WHERE
		c_name in %s
"""

path_to_csv = "/home/akhsig/git/code-home/pdfExtractor/indexation.csv"
csv = open(path_to_csv, 'r')
presentations = []
for line in csv:
	add = s.split(line, ',')[1];
	presentations.append(add.strip('"'));

in_filter = '"'+'","'.join(presentations)+'"'

query = """	SELECT
			*
		FROM
			_40_conference
		WHERE
			c_name in ("""
query += in_filter
query += ')'
cursor.execute(query)

print cursor.fetchall()

files = []
texts = []
problems = []
toolbar_width = 100
extract_dir = "/home/akhsig/git/code-home/pdfExtractor/files/SIU" # variable for the absolute path to directory for pdf files!

output_files = open('/home/akhsig/git/code-home/pdfExtractor/output_files.txt', 'w')
output_texts = open('/home/akhsig/git/code-home/pdfExtractor/output_texts.txt', 'w')
output_problems = open('/home/akhsig/git/code-home/pdfExtractor/output_problems.txt', 'w')

#get a list of the words on the GSL
#this reduces the number of elements 
#in the set of words from each document
#because we assume these words are less
#important; to be discussed?
gsl = open('gsl', 'r')
gsl_words_list = []
for line in gsl:
	gsl_words_list.append(line.split()[2])
gsl.close()

#now make it a set!
gsl_words = set(gsl_words_list)

test = os.listdir(extract_dir)
prefix = extract_dir

for f in test:
	if prefix[len(prefix)-1] != "/":
		prefix += "/"
	files.append(prefix+f)
#lines = test.split("\n")
'''
print "Parsing output of ls -lR"

# setup toolbar
sys.stdout.write("[%s]" % (" " * toolbar_width))
sys.stdout.flush()
sys.stdout.write("\b" * (toolbar_width+1)) # return to start of line, after '['

line_count = float(len(lines))
tmp = 0
current = 0

for line in lines:
	#parse the output of ls -Rl
	tmp += 1
	if line:
		if line[0] == "t":
			#do nothing, this means the line is not an actual file
			pass
		elif line[0] == "/":
			#this means we have a new prefix!
			prefix = line.split(":")[0]
		else:
			#this is a good file so we need to get only the filename!
			fil = s.split(line," ",8)
			print fil
			if "" in fil:
				#because certain filenames are shorter than others, ls will add spaces to its output so that everything looks good
				#we need to account for the number of spaces added in order to be able to isolate only the filename!
				fil = s.split(fil[8], " ", fil.count("") )[fil.count("")]
			else:
				fil = fil[8]
			if prefix[len(prefix)-1] != "/":
				prefix += "/"
			files.append(prefix+fil)
	temp = tmp/line_count * 100
	if temp > current:
		for i in range(int(temp-current)):
			sys.stdout.write("-")
    			sys.stdout.flush()
		current = temp

sys.stdout.write("\n")

#now, we have the filenames, so we can open them!
#consider all possible document types
'''
print "Reading and parsing files"

# setup toolbar
#sys.stdout.write("[%s]" % (" " * toolbar_width))
#sys.stdout.flush()
#sys.stdout.write("\b" * (toolbar_width+1)) # return to start of line, after '['
files_len = float(len(files))
current = 0
tmp = 0

for f in files:
	tmp += 1
	sys.stdout.write("\b" * (len(str(current))+1))
	text = ""
	ext = f.split('.')[f.count('.')]
	if ext == "ppt":
		#it's a ppt, need to use catppt tool!
		#make sure to handle errors!
		out = check_output(["catppt", f], stderr=sp.STDOUT)
		if out == f+" is not OLE file or Error":
			print f+" will be added to problematic files!"
			problems.append(f)
			#files.remove(f)
		else:
			#we don't have an error, out contains content of document
			out = set(s.replace(out,"\n"," ").encode('utf-8').lower().split())
			#out -= gsl_words
			texts.append(s.join(out," "))
	elif ext == "pptx":
		#for pptx, use a try since there seems to be many things that can go wrong with py-pptx...
		try:
			prs = Presentation(f)
		except (LookupError, KeyError):
			#something went wrong along the way, add file to problems and move on
			problems.append(f)
			#files.remove(f)
			sys.exc_clear()
			continue
		#we were able to open the file, read the content!
		#else:
		out = ""
		for slide in prs.slides:
			for shape in slide.shapes:
		        	if not shape.has_textframe:
		            		continue
       				for paragraph in shape.textframe.paragraphs:
					for run in paragraph.runs:
       	        				out += run.text+" "
		out = set(s.replace(out, "\n", " ").encode('utf-8').lower().split())
		#out -= gsl_words
		texts.append(s.join(out, " "))
	elif ext == "doc":
		#we have a doc file, use catdoc! if it doesnt work, we should get a segfault!
		try:
			out = check_output(['catdoc', f], stderr=sp.STDOUT)
		except sp.CalledProcessError:
			problems.append(f)
			sys.exc_clear()
			continue

		if out == "Segmentation fault (core dumped)":
			print f+" will be added to problems!"
			problems.append(f)
			#files.remove(f)
		else:
			#we have an output! parse it a little and add it to texts!
			out = set(s.replace(out, "\n", " ").encode('utf-8').lower().split())
			#out -= gsl_words
			texts.append(s.join(out, " "))
	elif ext == "docx":
		#we have a docx, use the perl script to try and extract content
		out = check_output(['/usr/bin/docx2txt.pl', f, '-'], stderr=sp.STDOUT)
		if out.startswith("Can't read docx file <") or out.startswith("Failed to extract required information from <"):
			#we have an error, add to problems!
			print f+" will be added to problems!"
                        problems.append(f)
			#files.remove(f)
		else:
			#out contains the output of the file
			out = set(s.replace(out, "\n", " ").encode('utf-8').lower().split())
                        #out -= gsl_words
                        texts.append(s.join(out, " "))
	#elif ext == "xls":  #for now dont need to support these files...
	#elif ext == "xlsx":
	elif ext == "pdf":
		pdf = p.PdfFileReader(open(str(f), "rb"))
		if pdf.isEncrypted:
			# we try and decrypt it!
			pdf.decrypt("")
		
		page_num = pdf.getNumPages()
		for i in range(page_num):
			page = pdf.getPage(i)
			text += s.replace(page.extractText(),"\n"," ")
		text = set(text.encode('utf-8').lower().split())
		#text -= gsl_words
		texts.append(s.join(text, " "))
	else: 
		#file type is something else
		#for now, add file to problems
		problems.append(f)
		#files.remove(f)
	
	temp = tmp/files_len*100
        if temp > current:
		sys.stdout.write(str(int(temp))+"%")
		sys.stdout.flush()
                #for i in range(int(temp-current)):
                #        sys.stdout.write("-")
                #        sys.stdout.flush()
                current = temp

sys.stdout.write("\n")

#now, we should have the content of all the files that could be opened and read and problems should be populated with files that need to be checked manually

print "Printing output to files!"

files = [x for x in files if x not in problems]

for prob in problems:
	output_problems.write(prob+"\n")

for i in range(len(files)):
	output_texts.write(files[i]+":"+texts[i]+"\n")

for f in files:
	output_files.write(f+"\n")

output_problems.close()
output_texts.close()
output_files.close()

