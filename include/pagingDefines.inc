; Night Kernel
; Copyright 2015 - 2020 by mercury0x0d
; paging defines.inc is a part of the Night Kernel

; The Night Kernel is free software: you can redistribute it and/or modify it under the terms of the GNU General Public
; License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later
; version.

; The Night Kernel is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
; warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

; You should have received a copy of the GNU General Public License along with the Night Kernel. If not, see
; <http://www.gnu.org/licenses/>.

; See the included file <GPL License.txt> for the complete text of the GPL License by which this program is covered.





%define PDEBigPage								0x80
%define PDEAccessed								0x20
%define PDECacheDisable							0x10
%define PDEWriteThrough							0x08
%define PDEUserAccessable						0x04
%define PDEWritable								0x02
%define PDEPresent								0x01





; declare functions as global
global PagingInit
global PagingMap
global PagingDirNew
