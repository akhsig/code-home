from subprocess import check_output
import subprocess

#test = check_output(["catppt", "/home/akhsig/code/pdfExtractor/files/practicepowerpoint.ppt"])
test2 = check_output(["catppt", "/home/akhsig/code/pdfExtractor/files/"],stderr=subprocess.STDOUT)

print test2
